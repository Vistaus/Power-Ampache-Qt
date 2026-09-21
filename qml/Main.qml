/*
 * Copyright (C) 2026  icefields
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 3.
 *
 * powerampache is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick 2.7
import Lomiri.Components 1.3
import io.thp.pyotherside 1.4
import "pages"
import "components"

MainView {
    id: root
    objectName: 'mainView'
    applicationName: 'powerampache.icefields'

    width: units.gu(45)
    height: units.gu(75)

    property bool justAuthenticated: false
    property bool wideModeAllowed: false
    readonly property bool wideMode: pageLayout.width > units.gu(80) && root.wideModeAllowed

    function formatDuration(totalSeconds) {
        var seconds = Math.max(0, Math.floor(totalSeconds))
        var minutes = Math.floor(seconds / 60)
        var remainder = seconds % 60
        return minutes + ':' + (remainder < 10 ? '0' : '') + remainder
    }

    AdaptivePageLayout {
        id: pageLayout
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            bottom: parent.bottom
            // The ONE reservation for the bottom bars: every page in the
            // stack ends above them. Per-view bottomMargin is forbidden.
            bottomMargin: (miniBar.visible ? miniBar.height : 0)
                          + (navBar.visible ? navBar.height : 0)
        }
        // Two-column desktop layout, gated on wideMode so the login page
        // never shows an empty right pane. No match (narrow or login) =
        // APL single-column fallback. min != max on col 2 = draggable divider.
        layouts: PageColumnsLayout {
            when: root.wideMode
            PageColumn { fillWidth: true }
            PageColumn {
                minimumWidth: units.gu(30)
                maximumWidth: units.gu(70)
                preferredWidth: units.gu(50)
            }
        }
    }

    Engine {
        id: engine
        pythonBridge: python
    }

    PlayerOverlay {
        id: playerOverlay
        miniBar: miniBar
        navBar: navBar
        playback: engine
        pythonBridge: python
        audioEngine: engine.audioElement
        formatDuration: root.formatDuration
        enabled: root.wideModeAllowed && !root.wideMode
    }

    MiniBar {
        id: miniBar
        playback: engine
        navBar: navBar
        overlayHandle: playerOverlay
        chevronIconName: playerOverlay.chevronIcon
        openPlayerCallback: function() { playerOverlay.tapAction() }
    }

    NavBar {
        id: navBar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        visible: root.wideModeAllowed && !root.wideMode
        pageLayout: pageLayout
        libraryPageComponent: libraryPageComponent
        albumPageComponent: albumPageComponent
        playerPageComponent: playerPageComponent
        playlistDetailPageComponent: playlistDetailPageComponent
        artistPageComponent: artistPageComponent
        wideMode: root.wideMode
    }

    Python {
        id: python

        Component.onCompleted: {
            addImportPath(Qt.resolvedUrl('../src/'))
            importModule('bridge', function() {
                python.call('bridge.init', [], function(initResult) {
                    if (!initResult || !initResult.ok) {
                        pageLayout.primaryPageSource = errorPageComponent
                        return
                    }
                    python.call('bridge.hasCredentials', [], function(credentialsResult) {
                        if (credentialsResult.ok && credentialsResult.hasCredentials) {
                            root.wideModeAllowed = true
                            pageLayout.primaryPageSource = homePageComponent
                        } else {
                            root.wideModeAllowed = false
                            pageLayout.primaryPageSource = loginPageComponent
                        }
                    })
                })
            })
        }

        onError: {
            console.log('python error: ' + traceback)
            if (pageLayout.primaryPage) {
                pageLayout.addPageToCurrentColumn(pageLayout.primaryPage,
                                                  errorPageComponent,
                                                  { message: i18n.tr('Internal error') })
            } else {
                pageLayout.primaryPageSource = errorPageComponent
            }
        }
    }

    Component {
        id: loginPageComponent
        LoginPage {
            pythonBridge: python
            authenticatedCallback: function() {
                root.justAuthenticated = true
                root.wideModeAllowed = true
                pageLayout.primaryPageSource = homePageComponent
            }
        }
    }

    Component {
        id: homePageComponent
        HomePage {
            pythonBridge: python
            mainView: root
            albumRowDelegate: albumRowComponent
        }
    }
    Component { id: albumPageComponent; AlbumPage { pythonBridge: python; playback: engine; formatDuration: root.formatDuration } }

    Component { id: artistPageComponent; ArtistPage { pythonBridge: python; openAlbumCallback: navBar.openAlbumFromArtist } }

    Component {
        id: playerPageComponent
        PlayerPage {
            playback: engine
            pythonBridge: python
            audioEngine: engine.audioElement
            formatDuration: root.formatDuration
        }
    }

    Component {
        id: libraryPageComponent
        LibraryPage {
            pythonBridge: python
            openPlaylistCallback: navBar.openPlaylist
            playback: engine
            formatDuration: root.formatDuration
            openAlbumCallback: navBar.openAlbumFromLibrary
            openArtistCallback: navBar.openArtist
        }
    }

    Component {
        id: playlistDetailPageComponent
        PlaylistDetailPage {
            pythonBridge: python
            playback: engine
            formatDuration: root.formatDuration
        }
    }

    Component {
        id: albumRowComponent
        AlbumRow {
            openAlbumCallback: function(albumId, albumName) {
                navBar.openAlbum(albumId, albumName)
            }
        }
    }

    Component { id: errorPageComponent; ErrorPage { } }
}
