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

    function formatDuration(totalSeconds) {
        var seconds = Math.max(0, Math.floor(totalSeconds))
        var minutes = Math.floor(seconds / 60)
        var remainder = seconds % 60
        return minutes + ':' + (remainder < 10 ? '0' : '') + remainder
    }

    PageStack {
        id: pageStack
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            bottom: parent.bottom
            // The ONE reservation for the mini-bar: every page in the
            // stack ends above the bar. Per-view bottomMargin lines are
            // forbidden from now on - this owns it.
            bottomMargin: miniBar.visible ? miniBar.height : 0
        }
    }

    Engine {
        id: engine
        pythonBridge: python
    }

    MiniBar {
        id: miniBar
        playback: engine
        openPlayerCallback: function() {
            // Guard against stacking a second player page.
            if (pageStack.currentPage.objectName !== 'playerPage') {
                pageStack.push(playerPageComponent)
            }
        }
    }

    Python {
        id: python

        Component.onCompleted: {
            addImportPath(Qt.resolvedUrl('../src/'))
            importModule('bridge', function() {
                python.call('bridge.init', [], function(initResult) {
                    if (!initResult || !initResult.ok) {
                        pageStack.push(errorPageComponent)
                        return
                    }
                    python.call('bridge.hasCredentials', [], function(credentialsResult) {
                        if (credentialsResult.ok && credentialsResult.hasCredentials) {
                            pageStack.push(homePageComponent)
                        } else {
                            pageStack.push(loginPageComponent)
                        }
                    })
                })
            })
        }

        onError: {
            console.log('python error: ' + traceback)
            pageStack.clear()
            pageStack.push(errorPageComponent, { message: i18n.tr('Internal error') })
        }
    }

    Component {
        id: loginPageComponent

        LoginPage {
            pythonBridge: python
            authenticatedCallback: function() {
                root.justAuthenticated = true
                pageStack.clear()
                pageStack.push(homePageComponent)
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

    Component {
        id: albumPageComponent

        AlbumPage {
            pythonBridge: python
            playback: engine
            formatDuration: root.formatDuration
        }
    }

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
        id: albumRowComponent

        AlbumRow {
            openAlbumCallback: function(albumId, albumName) {
                pageStack.push(albumPageComponent, {
                    albumId: albumId, albumName: albumName
                })
            }
        }
    }

    Component {
        id: errorPageComponent
        ErrorPage { }
    }
}
