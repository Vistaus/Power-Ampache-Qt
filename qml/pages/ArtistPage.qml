/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3
import "../components"

// Artist drill-down, header redesigned after the PA2 artist screen:
// fixed header = scrollable genre chips, song count + like (flag)
// button, play-all button; below it the artist's albums in a 2-per-row
// grid, newest first (the grid is the only scrollable element).
// artistId, artistName, pythonBridge, playback and
// openAlbumCallback(albumId, albumName) are injected at the use site.
Page {
    id: artistPage
    objectName: 'artistPage'

    property var artistId
    property string artistName
    property var pythonBridge
    property var playback
    property var openAlbumCallback

    // Replaced wholesale when the bridge answers.
    property var albums: []
    property int songCount: 0
    property var genres: []
    property bool artistFlag: false
    property bool artistSongsLoading: false
    property string artistArtUrl: ''
    property bool artistHasArt: false

    header: PageHeader {
        id: artistHeader
        title: artistPage.artistName
    }

    // Full-page artist art background, faint for readability.
    // Declared before the content: later children stack above it.
    Image {
        anchors.fill: parent
        visible: artistPage.artistHasArt
        source: artistPage.artistArtUrl
        fillMode: Image.PreserveAspectCrop
        opacity: 0.2
        asynchronous: true
    }

    // Fixed header content: genres, songs + like, play-all.
    Column {
        id: artistInfoColumn
        anchors {
            top: artistHeader.bottom
            topMargin: units.gu(1)
            left: parent.left
            right: parent.right
        }
        spacing: units.gu(1)

        // Genre chips: horizontally scrollable row of rounded squares.
        // Visual only - genre browse is a ROADMAP item.
        Flickable {
            width: parent.width
            height: artistPage.genres.length > 0 ? units.gu(6) : 0
            visible: artistPage.genres.length > 0
            contentWidth: genresRow.width + units.gu(4)
            contentHeight: height
            clip: true

            Row {
                id: genresRow
                x: units.gu(2)
                anchors.verticalCenter: parent.verticalCenter
                spacing: units.gu(1)

                Repeater {
                    model: artistPage.genres

                    delegate: Rectangle {
                        height: units.gu(4.5)
                        width: genreLabel.implicitWidth + units.gu(4.5)
                        radius: units.gu(1)
                        color: theme.palette.normal.base

                        Label {
                            id: genreLabel
                            anchors.centerIn: parent
                            text: modelData
                            fontSize: 'medium'
                        }
                    }
                }
            }
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
                // Mixed weight in one line: RichText <b> on the value
                // only. The count is an int - no HTML escaping needed.
                text: i18n.tr('Songs') + ' <b>' + artistPage.songCount + '</b>'
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
                    liked: artistPage.artistFlag
                    onToggled: {
                        var newFlag = !artistPage.artistFlag
                        artistPage.pythonBridge.call('bridge.flagArtist',
                            [artistPage.artistId, newFlag], function(result) {
                                if (result && result.ok) {
                                    artistPage.artistFlag = result.flag
                                } else {
                                    console.log('artistPage: flag failed '
                                                + (result ? result.message : 'null'))
                                }
                            })
                    }
                }
            }
        }

        // Play-all button (the only survivor of PA2's 4-button bar).
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
                    onClicked: artistPage.playAll()
                }
            }
        }
    }

    GridView {
        id: artistAlbumGridView
        anchors {
            top: artistInfoColumn.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        clip: true
        cellWidth: parent.width / 2
        cellHeight: cellWidth * 13 / 11
        model: artistPage.albums

        delegate: Item {
            width: artistAlbumGridView.cellWidth
            height: artistAlbumGridView.cellHeight

            LomiriShape {
                id: albumCoverShape
                anchors {
                    top: parent.top
                    topMargin: units.gu(1)
                    horizontalCenter: parent.horizontalCenter
                }
                width: artistAlbumGridView.cellWidth - units.gu(2)
                height: width
                radius: 'small'
                backgroundColor: 'transparent'
                sourceFillMode: LomiriShape.PreserveAspectCrop
                source: Image {
                    source: modelData.hasArt ? modelData.artUrl : Qt.resolvedUrl('../../assets/fallback/ic_speaker_colored_432px.svg')
                    asynchronous: true
                }
            }

            Label {
                anchors {
                    top: albumCoverShape.bottom
                    topMargin: units.gu(0.5)
                    left: parent.left
                    leftMargin: units.gu(1)
                    right: parent.right
                    rightMargin: units.gu(1)
                }
                text: modelData.name
                fontSize: 'small'
                font.bold: true
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }

            MouseArea {
                anchors.fill: parent
                onClicked: artistPage.openAlbumCallback(modelData.id, modelData.name)
            }
        }
    }

    function playAll() {
        if (artistPage.artistSongsLoading) {
            return
        }
        artistPage.artistSongsLoading = true
        pythonBridge.call('bridge.getArtistSongs', [artistPage.artistId], function(result) {
            artistPage.artistSongsLoading = false
            if (result && result.ok && result.songs.length > 0) {
                artistPage.playback.playFrom(result.songs, 0)
            } else {
                console.log('artistPage: playAll empty or failed '
                            + (result && !result.ok ? result.message : 'no songs'))
            }
        })
    }

    Component.onCompleted: {
        pythonBridge.call('bridge.getArtistInfo', [artistPage.artistId], function(result) {
            if (result && result.ok) {
                artistPage.songCount = result.songCount
                artistPage.genres = result.genres
                artistPage.artistFlag = result.flag
                artistPage.artistArtUrl = result.artUrl
                artistPage.artistHasArt = result.hasArt
            }
        })
        pythonBridge.call('bridge.getArtistAlbums', [artistPage.artistId], function(result) {
            if (result && result.ok) {
                artistPage.albums = result.albums
            }
        })
    }
}
