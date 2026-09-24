/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3
import "../components"

// Playlist drill-down, header redesigned after the artist/album pages:
// fixed header = Songs count (bold value) + like (flag) heart + play-all
// button; the track list below keeps album art rows (showArt). The list
// is the only scrollable element. Page background = the playlist cover,
// faint, when art exists. playlistId and playlistName arrive via
// push-with-properties (the Component wrapper in Main.qml makes them
// land here). pythonBridge (the Python element), playback (the queue
// manager) and formatDuration are injected at the use site.
Page {
    id: playlistDetailPage

    property var playlistId
    property string playlistName: ''
    property var pythonBridge
    property var playback
    property var formatDuration

    // Tracks in playlist-position order exactly as the bridge
    // returns them; never re-sort. This same array is handed to
    // queueManager.playFrom() on track tap.
    property var tracks: []

    // Header info from the cached PlaylistEntity row.
    property int songCount: 0
    property bool playlistFlag: false
    property string playlistArtUrl: ''
    property bool playlistHasArt: false

    header: PageHeader {
        id: playlistDetailHeader
        title: playlistDetailPage.playlistName
    }

    // Full-page playlist cover background, faint for readability.
    // Declared before the content: later children stack above it.
    Image {
        anchors.fill: parent
        visible: playlistDetailPage.playlistHasArt
        source: playlistDetailPage.playlistArtUrl
        fillMode: Image.PreserveAspectCrop
        opacity: 0.15
        asynchronous: true
    }

    // Fixed header content: songs + like, play-all.
    Column {
        id: playlistInfoColumn
        anchors {
            top: playlistDetailHeader.bottom
            topMargin: units.gu(0.5)
            left: parent.left
            right: parent.right
        }
        spacing: units.gu(1)

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
                text: i18n.tr('Songs') + ' <b>' + playlistDetailPage.songCount + '</b>'
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
                    liked: playlistDetailPage.playlistFlag
                    onToggled: {
                        var newFlag = !playlistDetailPage.playlistFlag
                        playlistDetailPage.pythonBridge.call('bridge.flagPlaylist',
                            [playlistDetailPage.playlistId, newFlag], function(result) {
                                if (result && result.ok) {
                                    playlistDetailPage.playlistFlag = result.flag
                                } else {
                                    console.log('playlistDetailPage: flag failed '
                                                + (result ? result.message : 'null'))
                                }
                            })
                    }
                }
            }
        }

        // Play-all button: the playlist from the first to the last track.
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

                Label {
                    // Optical centering: the glyph sits left-bottom in
                    // its em box - offsets nudge it right + up.
                    anchors {
                        horizontalCenter: parent.horizontalCenter
                        horizontalCenterOffset: units.gu(0.2)
                        verticalCenter: parent.verticalCenter
                        verticalCenterOffset: -units.gu(0.2)
                    }
                    text: '▶'
                    fontSize: 'large'
                    color: theme.palette.normal.base
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: playlistDetailPage.playAll()
                }
            }
        }
    }

    ListView {
        id: trackListView
        anchors {
            top: playlistInfoColumn.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        clip: true
        model: playlistDetailPage.tracks

        delegate: TrackDelegate {
            width: trackListView.width
            playTrackCallback: function(rowIndex) {
                playback.playFrom(playlistDetailPage.tracks, rowIndex)
            }
            formatDuration: playlistDetailPage.formatDuration
            showArt: true
        }
    }

    function playAll() {
        if (playlistDetailPage.tracks.length === 0) {
            console.log('playlistDetailPage: playAll skipped, no tracks loaded')
            return
        }
        playlistDetailPage.playback.playFrom(playlistDetailPage.tracks, 0)
    }

    Component.onCompleted: {
        pythonBridge.call('bridge.getPlaylistInfo', [playlistDetailPage.playlistId], function(result) {
            if (result && result.ok) {
                playlistDetailPage.songCount = result.songCount
                playlistDetailPage.playlistFlag = result.flag
                playlistDetailPage.playlistArtUrl = result.artUrl
                playlistDetailPage.playlistHasArt = result.hasArt
            }
        })
        pythonBridge.call('bridge.getPlaylistSongs', [playlistDetailPage.playlistId], function(result) {
            if (result && result.ok) {
                playlistDetailPage.tracks = result.songs
            }
            // On failure the page stays empty; session 3 owns error
            // surfacing.
        })
    }
}
