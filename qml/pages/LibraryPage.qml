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

    // Search state. searchActive derives from the mode plus the
    // minimum query length; browse models are never overwritten,
    // the views bind through a ternary on searchActive.
    property bool searchMode: false
    property string searchQuery: ''
    property var searchResults: []
    property bool searchRunning: false
    property int searchGeneration: 0
    readonly property bool searchActive: searchMode && searchQuery.length >= 2

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

    function toggleSearch() {
        searchMode = !searchMode
        // Invalidate any in-flight search so a late response cannot
        // write into the cleared state.
        searchGeneration += 1
        searchRunning = false
        if (!searchMode) {
            // Clearing the field runs onTextChanged, which clears
            // searchQuery and searchResults and stops the debounce.
            searchField.text = ''
        }
    }

    function runSearch() {
        if (!searchMode || searchQuery.length < 2) return
        libraryPage.searchGeneration += 1
        var generation = libraryPage.searchGeneration
        searchRunning = true
        searchResults = []   // clear before the call - no stale flash
        var sectionIndex = libraryHeader.sections.selectedIndex
        var methods = ['bridge.searchPlaylists', 'bridge.searchAlbums',
                       'bridge.searchSongs', 'bridge.searchArtists']
        var resultKeys = ['playlists', 'albums', 'songs', 'artists']
        pythonBridge.call(methods[sectionIndex], [libraryPage.searchQuery], function(result) {
            if (generation !== libraryPage.searchGeneration) return   // stale response - a newer search owns the field
            libraryPage.searchRunning = false
            if (result && result.ok) {
                libraryPage.searchResults = result[resultKeys[sectionIndex]] || []
                console.log('libraryPage: search section=' + sectionIndex
                            + ' rows=' + libraryPage.searchResults.length)
            }
            // On failure the (empty) result set stands; session 3
            // owns error surfacing.
        })
    }

    header: PageHeader {
        id: libraryHeader
        title: i18n.tr('Library')
        // sections is read-only: the model is assigned imperatively
        // in Component.onCompleted, never inline here.
        trailingActionBar.actions: Action {
            iconName: 'search'
            onTriggered: libraryPage.toggleSearch()
        }
    }

    // Search row: one field, contextual to the active section. The
    // debounce keeps every keystroke from firing a server request.
    Item {
        id: searchRow
        anchors {
            top: libraryHeader.bottom
            left: parent.left
            right: parent.right
        }
        height: libraryPage.searchMode ? units.gu(7) : 0
        visible: libraryPage.searchMode
        clip: true

        TextField {
            id: searchField
            anchors {
                left: parent.left
                leftMargin: units.gu(2)
                right: searchCloseIcon.left
                rightMargin: units.gu(1)
                verticalCenter: parent.verticalCenter
            }
            placeholderText: i18n.tr('Search')
            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
            onTextChanged: {
                libraryPage.searchQuery = text.trim()
                if (libraryPage.searchQuery.length >= 2) {
                    searchDebounce.restart()
                } else {
                    // Below the minimum: stop any pending search, the
                    // browse view is restored instantly.
                    searchDebounce.stop()
                    libraryPage.searchResults = []
                }
            }
        }

        Icon {
            id: searchCloseIcon
            anchors {
                right: parent.right
                rightMargin: units.gu(2)
                verticalCenter: parent.verticalCenter
            }
            width: units.gu(3)
            height: width
            name: 'close'

            MouseArea {
                anchors.fill: parent
                onClicked: libraryPage.toggleSearch()
            }
        }
    }

    Timer {
        id: searchDebounce
        interval: 450
        // repeat defaults to false: one shot per keystroke pause.
        onTriggered: libraryPage.runSearch()
    }

    Connections {
        target: libraryHeader.sections
        onSelectedIndexChanged: {
            // Hopping sections re-searches the same query; the field
            // and its text stay.
            if (libraryPage.searchActive) {
                libraryPage.runSearch()
            }
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
            top: searchRow.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        visible: libraryHeader.sections.selectedIndex === 0
        clip: true
        model: (libraryPage.searchActive && libraryHeader.sections.selectedIndex === 0)
               ? libraryPage.searchResults : libraryPage.playlists

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
                    source: modelData.hasArt ? modelData.artUrl : Qt.resolvedUrl('../../assets/fallback/ic_speaker_colored_432px.svg')
                    asynchronous: true
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

    Label {
        anchors.centerIn: playlistListView
        text: i18n.tr('No results')
        visible: libraryHeader.sections.selectedIndex === 0
                 && libraryPage.searchActive && !libraryPage.searchRunning
                 && libraryPage.searchResults.length === 0
    }

    GridView {
        id: albumGridView
        anchors {
            top: searchRow.bottom
            left: parent.left
            right: parent.right
            bottom: loadMoreAlbumsButton.top
        }
        visible: libraryHeader.sections.selectedIndex === 1
        clip: true
        cellWidth: parent.width / 3
        cellHeight: cellWidth * 14 / 11
        model: (libraryPage.searchActive && libraryHeader.sections.selectedIndex === 1)
               ? libraryPage.searchResults : libraryPage.albums

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
                onClicked: libraryPage.openAlbumCallback(modelData.id, modelData.name)
            }
        }
    }

    Label {
        anchors.centerIn: albumGridView
        text: i18n.tr('No results')
        visible: libraryHeader.sections.selectedIndex === 1
                 && libraryPage.searchActive && !libraryPage.searchRunning
                 && libraryPage.searchResults.length === 0
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
        height: visible ? units.gu(5) : 0
        visible: libraryHeader.sections.selectedIndex === 1 && !libraryPage.albumsComplete && !libraryPage.searchActive

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
            top: searchRow.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        visible: libraryHeader.sections.selectedIndex === 2
        clip: true
        model: (libraryPage.searchActive && libraryHeader.sections.selectedIndex === 2)
               ? libraryPage.searchResults : libraryPage.recentSongs

        delegate: TrackDelegate {
            width: recentSongsListView.width
            playTrackCallback: function(rowIndex) {
                // v1 semantics: the tapped song plays as a queue of one.
                var songs = libraryPage.searchActive ? libraryPage.searchResults : libraryPage.recentSongs
                playback.playFrom([songs[rowIndex]], 0)
            }
            formatDuration: libraryPage.formatDuration
        }
    }

    Label {
        anchors.centerIn: recentSongsListView
        text: i18n.tr('No results')
        visible: libraryHeader.sections.selectedIndex === 2
                 && libraryPage.searchActive && !libraryPage.searchRunning
                 && libraryPage.searchResults.length === 0
    }

    GridView {
        id: artistGridView
        anchors {
            top: searchRow.bottom
            left: parent.left
            right: parent.right
            bottom: loadMoreArtistsButton.top
        }
        visible: libraryHeader.sections.selectedIndex === 3
        clip: true
        cellWidth: parent.width / 4
        cellHeight: cellWidth * 16 / 11
        model: (libraryPage.searchActive && libraryHeader.sections.selectedIndex === 3)
               ? libraryPage.searchResults : libraryPage.artists

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
                    source: modelData.hasArt ? modelData.artUrl : Qt.resolvedUrl('../../assets/fallback/ic_speaker_colored_432px.svg')
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

    Label {
        anchors.centerIn: artistGridView
        text: i18n.tr('No results')
        visible: libraryHeader.sections.selectedIndex === 3
                 && libraryPage.searchActive && !libraryPage.searchRunning
                 && libraryPage.searchResults.length === 0
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
        height: visible ? units.gu(5) : 0
        visible: libraryHeader.sections.selectedIndex === 3 && !libraryPage.artistsComplete && !libraryPage.searchActive

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
