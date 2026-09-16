/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3
import "../components"

// Library browser. The header's built-in Sections switch the body:
// Playlists, Albums (chunked grid), Songs (recently played) and
// Artists (chunked grid). pythonBridge (the Python element),
// openPlaylistCallback(playlistId, playlistName), playback (the
// queue manager), formatDuration(seconds),
// openAlbumCallback(albumId, albumName) and
// openArtistCallback(artistId, artistName) are injected at the use
// site.
Page {
    id: libraryPage
    objectName: 'libraryPage'

    property var pythonBridge
    property var openPlaylistCallback
    property var playback
    property var formatDuration
    property var openAlbumCallback
    property var openArtistCallback

    // The Albums and Artists grid models are both replaced wholesale
    // on every chunk (the bridge returns the full sorted cache);
    // recentSongs is replaced wholesale on every Songs selection.
    property var albums: []
    property var artists: []
    property var recentSongs: []
    property bool albumsComplete: false
    property bool albumsLoaded: false
    property bool artistsComplete: false
    property bool artistsLoaded: false
    property bool albumsFetching: false
    property bool artistsFetching: false
    property int albumsOffset: 0
    property int artistsOffset: 0

    // Playlist dicts in the order the bridge returns them.
    property var playlists: []

    function loadAlbumsChunk() {
        if (albumsFetching) return
        albumsFetching = true
        pythonBridge.call('bridge.getAlbumsPage', [libraryPage.albumsOffset, 100], function(result) {
            libraryPage.albumsFetching = false
            if (result && result.ok) {
                libraryPage.albums = result.albums
                libraryPage.albumsComplete = result.complete
                libraryPage.albumsOffset += result.fetched   // server chunk size, not the cache size - the cache read-back is cumulative
                libraryPage.albumsLoaded = true
                console.log('libraryPage: albums chunk offset=' + libraryPage.albumsOffset
                            + ' rows=' + result.fetched + ' complete=' + result.complete)
            }
            // On failure the section keeps what it has; session 3
            // owns error surfacing.
        })
    }

    function loadRecentSongs() {
        pythonBridge.call('bridge.getRecentSongs', [50], function(result) {
            if (result && result.ok) {
                libraryPage.recentSongs = result.songs
                console.log('libraryPage: recent songs rows=' + result.songs.length)
            }
        })
    }

    function loadArtistsChunk() {
        if (artistsFetching) return
        artistsFetching = true
        pythonBridge.call('bridge.getArtistsPage', [libraryPage.artistsOffset, 100], function(result) {
            libraryPage.artistsFetching = false
            if (result && result.ok) {
                libraryPage.artists = result.artists
                libraryPage.artistsComplete = result.complete
                libraryPage.artistsOffset += result.fetched   // server page size, not the cache size - the cache read-back is cumulative
                libraryPage.artistsLoaded = true
                console.log('libraryPage: artists chunk offset=' + libraryPage.artistsOffset
                            + ' rows=' + result.fetched + ' complete=' + result.complete)
            }
        })
    }

    header: PageHeader {
        id: libraryHeader
        title: i18n.tr('Library')
        // sections is read-only: the model is assigned imperatively
        // in Component.onCompleted, never inline here.
    }

    Connections {
        target: libraryHeader.sections
        onSelectedIndexChanged: {
            // Songs refetches every selection (the recent list
            // changes as you play); Albums/Artists fetch chunk 0
            // on first selection only.
            if (libraryHeader.sections.selectedIndex === 1 && !libraryPage.albumsLoaded) {
                libraryPage.loadAlbumsChunk()
            } else if (libraryHeader.sections.selectedIndex === 2) {
                libraryPage.loadRecentSongs()
            } else if (libraryHeader.sections.selectedIndex === 3 && !libraryPage.artistsLoaded) {
                libraryPage.loadArtistsChunk()
            }
        }
    }

    ListView {
        id: playlistListView
        anchors {
            top: libraryHeader.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        visible: libraryHeader.sections.selectedIndex === 0
        clip: true
        model: libraryPage.playlists

        delegate: Item {
            id: playlistRow
            width: playlistListView.width
            height: units.gu(9)

            // Fixed square cover (same height:width idiom as the
            // album-row cards); LomiriShape supplies the rounded
            // corners. Whatever a server artUrl returns is shown
            // as-is - no blank-art detection.
            LomiriShape {
                id: coverShape
                anchors {
                    left: parent.left
                    leftMargin: units.gu(2)
                    verticalCenter: parent.verticalCenter
                }
                width: units.gu(7)
                height: width
                radius: 'small'
                backgroundColor: theme.palette.normal.base
                sourceFillMode: LomiriShape.PreserveAspectCrop
                source: Image {
                    source: modelData.artUrl || ''
                    asynchronous: true
                }

                Icon {
                    anchors.centerIn: parent
                    width: units.gu(3)
                    height: units.gu(3)
                    name: 'view-list-symbolic'
                    visible: !modelData.artUrl
                }
            }

            Column {
                anchors {
                    left: coverShape.right
                    leftMargin: units.gu(1.5)
                    right: parent.right
                    rightMargin: units.gu(2)
                    verticalCenter: parent.verticalCenter
                }
                spacing: units.gu(0.2)

                Label {
                    width: parent.width
                    text: modelData.name
                    fontSize: 'medium'
                    font.bold: true
                    elide: Text.ElideRight
                }

                Label {
                    width: parent.width
                    text: modelData.owner + ' - '
                          + (modelData.items === null ? 0 : modelData.items)
                          + ' ' + i18n.tr('tracks')
                    fontSize: 'small'
                    elide: Text.ElideRight
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: libraryPage.openPlaylistCallback(modelData.id, modelData.name)
            }
        }
    }

    GridView {
        id: albumGridView
        anchors {
            top: libraryHeader.bottom
            left: parent.left
            right: parent.right
            bottom: loadMoreAlbumsButton.top
        }
        visible: libraryHeader.sections.selectedIndex === 1
        clip: true
        cellWidth: parent.width / 3
        cellHeight: cellWidth * 14 / 11
        model: libraryPage.albums

        delegate: Item {
            width: albumGridView.cellWidth
            height: albumGridView.cellHeight

            LomiriShape {
                id: albumCoverShape
                anchors {
                    top: parent.top
                    topMargin: units.gu(1)
                    horizontalCenter: parent.horizontalCenter
                }
                width: albumGridView.cellWidth - units.gu(2)
                height: width
                radius: 'small'
                backgroundColor: theme.palette.normal.base
                sourceFillMode: LomiriShape.PreserveAspectCrop
                source: Image {
                    source: modelData.artUrl || ''
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
                onClicked: libraryPage.openAlbumCallback(modelData.id, modelData.name)
            }
        }
    }

    Item {
        id: loadMoreAlbumsButton
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: units.gu(2)
            rightMargin: units.gu(2)
            bottomMargin: units.gu(1)
        }
        height: units.gu(5)
        visible: libraryHeader.sections.selectedIndex === 1 && !libraryPage.albumsComplete

        Label {
            anchors.centerIn: parent
            text: i18n.tr('Load more')
            color: theme.palette.normal.backgroundSecondaryText
            opacity: loadMoreMouseArea.pressed ? 0.4 : 1.0   // quiet press feedback, no chrome
        }

        MouseArea {
            id: loadMoreMouseArea
            anchors.fill: parent
            onClicked: libraryPage.loadAlbumsChunk()
        }
    }

    ListView {
        id: recentSongsListView
        anchors {
            top: libraryHeader.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        visible: libraryHeader.sections.selectedIndex === 2
        clip: true
        model: libraryPage.recentSongs

        delegate: TrackDelegate {
            width: recentSongsListView.width
            playTrackCallback: function(rowIndex) {
                // v1 semantics: the tapped song plays as a queue of one.
                playback.playFrom([libraryPage.recentSongs[rowIndex]], 0)
            }
            formatDuration: libraryPage.formatDuration
        }
    }

    GridView {
        id: artistGridView
        anchors {
            top: libraryHeader.bottom
            left: parent.left
            right: parent.right
            bottom: loadMoreArtistsButton.top
        }
        visible: libraryHeader.sections.selectedIndex === 3
        clip: true
        cellWidth: parent.width / 4
        cellHeight: cellWidth * 16 / 11
        model: libraryPage.artists

        delegate: Item {
            width: artistGridView.cellWidth
            height: artistGridView.cellHeight

            LomiriShape {
                id: artistCoverShape
                anchors {
                    top: parent.top
                    topMargin: units.gu(1)
                    horizontalCenter: parent.horizontalCenter
                }
                width: artistGridView.cellWidth - units.gu(2)
                height: width
                radius: 'small'
                backgroundColor: theme.palette.normal.base
                sourceFillMode: LomiriShape.PreserveAspectCrop
                source: Image {
                    source: modelData.artUrl || ''
                    asynchronous: true
                }
            }

            Label {
                id: artistNameLabel
                anchors {
                    top: artistCoverShape.bottom
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

            Label {
                anchors {
                    top: artistNameLabel.bottom
                    left: parent.left
                    leftMargin: units.gu(1)
                    right: parent.right
                    rightMargin: units.gu(1)
                }
                text: modelData.albumCount + ' ' + i18n.tr('albums') + ', '
                      + modelData.songCount + ' ' + i18n.tr('songs')
                fontSize: 'x-small'
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }

            MouseArea {
                anchors.fill: parent
                onClicked: libraryPage.openArtistCallback(modelData.id, modelData.name)
            }
        }
    }

    Item {
        id: loadMoreArtistsButton
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: units.gu(2)
            rightMargin: units.gu(2)
            bottomMargin: units.gu(1)
        }
        height: units.gu(5)
        visible: libraryHeader.sections.selectedIndex === 3 && !libraryPage.artistsComplete

        Label {
            anchors.centerIn: parent
            text: i18n.tr('Load more')
            color: theme.palette.normal.backgroundSecondaryText
            opacity: loadMoreArtistsMouseArea.pressed ? 0.4 : 1.0   // quiet press feedback, no chrome
        }

        MouseArea {
            id: loadMoreArtistsMouseArea
            anchors.fill: parent
            onClicked: libraryPage.loadArtistsChunk()
        }
    }

    Component.onCompleted: {
        // sections is read-only: populate the model imperatively.
        // Assigning the model resets selectedIndex, so the default
        // is set after it.
        libraryHeader.sections.model = [
            i18n.tr('Playlists'),
            i18n.tr('Albums'),
            i18n.tr('Songs'),
            i18n.tr('Artists')
        ]
        libraryHeader.sections.selectedIndex = 0
        pythonBridge.call('bridge.getPlaylists', [], function(result) {
            if (result && result.ok) {
                libraryPage.playlists = result.playlists
            }
            // On failure the page stays empty; session 3 owns error
            // surfacing.
        })
    }
}
