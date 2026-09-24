/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3
import "../components"

// Album drill-down, header redesigned after the artist page: fixed
// header = featured-artist pill row (darker pills) + genre pill row +
// Year / Songs / Total Time lines (bold values) + like (flag) heart +
// play-all button; the track list below KEEPS track numbers (the album
// is a numbered sequence - deliberate). The list is the only scrollable
// element. Page background = the album cover, faint, when art exists.
// albumId and albumName arrive via push-with-properties (the Component
// wrapper in Main.qml makes them land here). pythonBridge (the Python
// element), playback (the queue manager) and formatDuration are injected
// at the use site.
Page {
    id: albumPage

    property var albumId
    property string albumName: ''
    property var pythonBridge
    property var playback
    property var formatDuration
    // Assigned directly by NavBar on the incubated instance in
    // two-column mode (function references do not survive APL
    // creation-properties injection); single-column mounts leave
    // both untouched, so the header is unchanged there.
    property var closeCallback: null
    property bool wideMount: false

    // Tracks in the order the bridge returns them; this same array
    // is handed to queueManager.playFrom() on track tap.
    property var tracks: []

    // Header info from the cached AlbumEntity row.
    property string albumArtistName: ''
    property int albumYear: 0
    property int totalTime: 0
    property int songCount: 0
    property var genres: []
    property var artists: []
    property bool albumFlag: false
    property string albumArtUrl: ''
    property bool albumHasArt: false

    header: PageHeader {
        id: albumPageHeader
        title: albumPage.albumName

        trailingActionBar.actions: [
            Action {
                iconName: 'close'
                text: i18n.tr('Close')
                visible: albumPage.wideMount
                onTriggered: albumPage.closeCallback()
            }
        ]
    }

    // Full-page album cover background, faint for readability.
    // Declared before the content: later children stack above it.
    Image {
        anchors.fill: parent
        visible: albumPage.albumHasArt
        source: albumPage.albumArtUrl
        fillMode: Image.PreserveAspectCrop
        opacity: 0.15
        asynchronous: true
    }

    // Fixed header content: pills, info lines, like, play-all.
    Column {
        id: albumInfoColumn
        anchors {
            top: albumPageHeader.bottom
            topMargin: units.gu(0.5)
            left: parent.left
            right: parent.right
        }
        spacing: units.gu(1)

        // Featured artists - darker pills to distinguish from genres.
        PillRow {
            width: parent.width
            model: albumPage.artists
            pillColor: Qt.darker(theme.palette.normal.base, 1.5)
        }

        // Genres.
        PillRow {
            width: parent.width
            model: albumPage.genres
        }

        // Year (hidden when the server has none stored).
        Label {
            anchors {
                left: parent.left
                leftMargin: units.gu(2)
            }
            visible: albumPage.albumYear > 0
            text: i18n.tr('Year') + ' <b>' + albumPage.albumYear + '</b>'
            textFormat: Text.RichText
        }

        // Song count left, like (flag) button right.
        Item {
            width: parent.width
            height: units.gu(4)

            Label {
                anchors {
                    left: parent.left
                    leftMargin: units.gu(2)
                    verticalCenter: parent.verticalCenter
                }
                text: i18n.tr('Songs') + ' <b>' + albumPage.songCount + '</b>'
                textFormat: Text.RichText
            }

            Item {
                anchors {
                    right: parent.right
                    rightMargin: units.gu(2)
                    verticalCenter: parent.verticalCenter
                }
                width: units.gu(4)
                height: units.gu(4)

                HeartButton {
                    anchors.centerIn: parent
                    liked: albumPage.albumFlag
                    onToggled: {
                        var newFlag = !albumPage.albumFlag
                        albumPage.pythonBridge.call('bridge.flagAlbum',
                            [albumPage.albumId, newFlag], function(result) {
                                if (result && result.ok) {
                                    albumPage.albumFlag = result.flag
                                } else {
                                    console.log('albumPage: flag failed '
                                                + (result ? result.message : 'null'))
                                }
                            })
                    }
                }
            }
        }

        // Total time (hidden when the server has none stored).
        Label {
            anchors {
                left: parent.left
                leftMargin: units.gu(2)
            }
            visible: albumPage.totalTime > 0
            text: i18n.tr('Total Time') + ' <b>'
                  + Math.floor(albumPage.totalTime / 60) + 'm '
                  + (albumPage.totalTime % 60) + 's</b>'
            textFormat: Text.RichText
        }

        // Play-all button: the album from the first to the last track.
        Item {
            width: parent.width
            height: units.gu(9)

            Rectangle {
                id: playAllButton
                width: units.gu(7)
                height: units.gu(7)
                radius: width / 2
                anchors.centerIn: parent
                color: theme.palette.normal.baseText

                // Painted triangle, NOT a text glyph: '▶' falls back
                // to the color emoji font on this platform and ignores
                // the color property (dark-mode bug). Canvas = themed,
                // deterministic. Slight rightward optical nudge kept.
                Canvas {
                    anchors {
                        verticalCenter: parent.verticalCenter
                        horizontalCenter: parent.horizontalCenter
                        horizontalCenterOffset: units.gu(0.2)
                    }
                    width: units.gu(2.2)
                    height: units.gu(2.6)
                    antialiasing: true
                    onPaint: {
                        var ctx = getContext('2d')
                        ctx.reset()
                        ctx.fillStyle = theme.palette.normal.base
                        ctx.beginPath()
                        ctx.moveTo(0, 0)
                        ctx.lineTo(0, height)
                        ctx.lineTo(width, height / 2)
                        ctx.closePath()
                        ctx.fill()
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: albumPage.playAll()
                }
            }
        }
    }

    ListView {
        id: trackListView
        anchors {
            top: albumInfoColumn.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        clip: true
        model: albumPage.tracks

        delegate: TrackDelegate {
            width: trackListView.width
            playTrackCallback: function(rowIndex) {
                playback.playFrom(albumPage.tracks, rowIndex)
            }
            formatDuration: albumPage.formatDuration
        }
    }

    function playAll() {
        if (albumPage.tracks.length === 0) {
            console.log('albumPage: playAll skipped, no tracks loaded')
            return
        }
        albumPage.playback.playFrom(albumPage.tracks, 0)
    }

    Component.onCompleted: {
        pythonBridge.call('bridge.getAlbumInfo', [albumPage.albumId], function(result) {
            if (result && result.ok) {
                albumPage.albumArtistName = result.artistName
                albumPage.albumYear = result.year
                albumPage.totalTime = result.time
                albumPage.songCount = result.songCount
                albumPage.genres = result.genres
                albumPage.artists = result.artists
                albumPage.albumFlag = result.flag
                albumPage.albumArtUrl = result.artUrl
                albumPage.albumHasArt = result.hasArt
            }
        })
        pythonBridge.call('bridge.getAlbumSongs', [albumPage.albumId], function(result) {
            if (result && result.ok) {
                albumPage.tracks = result.songs
            }
            // On failure the page stays empty; session 3 owns error
            // surfacing.
        })
    }
}
