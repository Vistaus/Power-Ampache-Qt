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
    property bool wideModeFlipPending: false
    property int wideModeFlipRetries: 0
    property bool wideModeAllowed: false
    readonly property bool wideMode: pageLayout.width > units.gu(80) && root.wideModeAllowed

    function formatDuration(totalSeconds) {
        var seconds = Math.max(0, Math.floor(totalSeconds))
        var minutes = Math.floor(seconds / 60)
        var remainder = seconds % 60
        return minutes + ':' + (remainder < 10 ? '0' : '') + remainder
    }

    function logoutToLogin() {
        engine.stopEverything()
        wideModeFlipPending = false
        wideModeDelayTimer.stop()
        wideModeAllowed = false
        pageLayout.primaryPageSource = loginPageComponent
    }

    Timer {
        id: wideModeDelayTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (!root.wideModeFlipPending) {
                // A logout inside the deferral window cancelled the flip.
                return
            }
            // Flip only once the APL tree has actually settled: the new
            // primary page exists AND is registered in the layout
            // (parent non-null - the same settle test maybeMountLibrary
            // uses in NavBar).
            if (pageLayout.primaryPage !== null
                    && pageLayout.primaryPage.parent !== null) {
                root.wideModeAllowed = true
                root.wideModeFlipPending = false
                root.wideModeFlipRetries = 0
                console.log('main: wide mode enabled after settle')
            } else if (root.wideModeFlipRetries < 20) {
                root.wideModeFlipRetries = root.wideModeFlipRetries + 1
                console.log('main: wide-mode flip deferred, retry '
                    + root.wideModeFlipRetries)
                wideModeDelayTimer.restart()
            } else {
                // Give up honestly: stay single-column rather than flip
                // into an unsettled tree.
                root.wideModeFlipPending = false
                console.log('main: wide-mode flip gave up after 20 retries')
            }
        }
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

    MiniBar {
        id: miniBar
        playback: engine
        navBar: navBar
        overlayHandle: playerOverlay
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
        settingsPageComponent: settingsPageComponent
        aboutPageComponent: aboutPageComponent
        wideMode: root.wideMode
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

    // Theme application: 'dark' -> SuruDark, 'light' -> Ambiance,
    // 'system' -> untouched (the phone's platform integration follows
    // the OS; desktop has none, so the toolkit default stays).
    // Theme.name is settable at runtime - applied live, no restart.
    function applyTheme(theme) {
        if (theme === 'dark') {
            Theme.name = 'Lomiri.Components.Themes.SuruDark'
        } else if (theme === 'light') {
            Theme.name = 'Lomiri.Components.Themes.Ambiance'
        }
        console.log('main: theme applied=' + theme
                    + ' Theme.name=' + Theme.name)
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
                    python.call('bridge.getThemeSetting', [], function(themeResult) {
                        if (themeResult && themeResult.ok) {
                            root.applyTheme(themeResult.theme)
                        }
                    })
                    python.call('bridge.hasCredentials', [], function(credentialsResult) {
                        if (credentialsResult.ok && credentialsResult.hasCredentials) {
                            pageLayout.primaryPageSource = homePageComponent
                            root.wideModeFlipRetries = 0
                            root.wideModeFlipPending = true
                            wideModeDelayTimer.restart()
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
                pageLayout.primaryPageSource = homePageComponent
                root.wideModeFlipRetries = 0
                root.wideModeFlipPending = true
                wideModeDelayTimer.restart()
            }
        }
    }

    Component {
        id: homePageComponent
        HomePage {
            pythonBridge: python
            mainView: root
            albumRowDelegate: albumRowComponent
            openSettingsCallback: navBar.openSettings
            openAboutCallback: navBar.openAbout
        }
    }
    Component { id: albumPageComponent; AlbumPage { pythonBridge: python; playback: engine; formatDuration: root.formatDuration } }

    Component { id: artistPageComponent; ArtistPage { pythonBridge: python; playback: engine; openAlbumCallback: navBar.openAlbumFromArtist } }

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
        id: settingsPageComponent
        SettingsPage {
            pythonBridge: python
            logoutCallback: function() { root.logoutToLogin() }
        }
    }

    Component {
        id: aboutPageComponent
        AboutPage { pythonBridge: python }
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
