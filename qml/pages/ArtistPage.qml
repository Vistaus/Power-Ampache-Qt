/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3

// Artist drill-down: the artist's albums in a grid, newest first.
// artistId, artistName, pythonBridge (the Python element) and
// openAlbumCallback(albumId, albumName) are injected at the use site.
Page {
    id: artistPage
    objectName: 'artistPage'

    property var artistId
    property string artistName
    property var pythonBridge
    property var openAlbumCallback

    // Replaced wholesale when the bridge answers.
    property var albums: []

    header: PageHeader {
        id: artistHeader
        title: artistPage.artistName
    }

    GridView {
        id: artistAlbumGridView
        anchors {
            top: artistHeader.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        clip: true
        cellWidth: parent.width / 3
        cellHeight: cellWidth * 14 / 11
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
                backgroundColor: theme.palette.normal.base
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

    Component.onCompleted: {
        pythonBridge.call('bridge.getArtistAlbums', [artistPage.artistId], function(result) {
            if (result && result.ok) {
                artistPage.albums = result.albums
                console.log('artistPage: albums artistId=' + artistPage.artistId
                            + ' rows=' + result.albums.length)
            }
            // On failure the page stays empty; session 3 owns error
            // surfacing.
        })
    }
}
