/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3
import QtGraphicalEffects 1.0
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
    property bool albumsLoading: false
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

            Item {
                id: playAllButton
                width: units.gu(7)
                height: units.gu(7)
                anchors.centerIn: parent

                // Glyph asset (black ring + triangle). Hidden: it is the
                // MASK source, not a renderer (same rule as the avatar:
                // a visible source under OpacityMask leaks its own color
                // around the tint).
                Image {
                    id: playGlyphMask
                    anchors.fill: parent
                    source: Qt.resolvedUrl('../../assets/icons/circle-play.svg')
                    asynchronous: true
                    visible: false
                }

                // Tint source: themed color, REACTIVE on theme change
                // (declarative palette binding - this is what Canvas
                // could not do).
                Rectangle {
                    id: playGlyphTint
                    anchors.fill: parent
                    color: theme.palette.normal.baseText
                    visible: false
                }

                OpacityMask {
                    anchors.fill: parent
                    source: playGlyphTint
                    maskSource: playGlyphMask
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

    ViewState {
        anchors {
            top: artistInfoColumn.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        busy: artistPage.albumsLoading
        empty: artistPage.albums.length === 0
        emptyMessage: i18n.tr('No albums')
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
        artistPage.albumsLoading = true
        pythonBridge.call('bridge.getArtistAlbums', [artistPage.artistId], function(result) {
            artistPage.albumsLoading = false
            if (result && result.ok) {
                artistPage.albums = result.albums
            }
        })
    }
}
