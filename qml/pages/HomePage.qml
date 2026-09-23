/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3
import "../components"
import Lomiri.Components.Popups 1.3

// Home dashboard: six stat rows of album covers, rendered cache-first
// with background refreshes. pythonBridge (the Python element),
// mainView (the MainView root, read/written for the justAuthenticated
// flag) and albumRowDelegate (the Component producing AlbumRow
// instances) are injected at the use site.
Page {
    id: homePage

    property var pythonBridge
    property var mainView
    property var albumRowDelegate
    property var openSettingsCallback: null
    property var openAboutCallback: null
    property string username: ''
    property string serverUrl: ''

    header: PageHeader {
        id: pageHeader
        title: i18n.tr('Power Ampache')
        contents: Item {
            anchors.fill: parent

            Row {
                anchors {
                    left: parent.left
                    leftMargin: units.gu(1.5)
                    verticalCenter: parent.verticalCenter
                }
                spacing: units.gu(1.5)

                Rectangle {
                    id: avatarCircle
                    width: units.gu(4)
                    height: units.gu(4)
                    radius: width / 2
                    color: theme.palette.normal.base
                    anchors.verticalCenter: parent.verticalCenter

                    Label {
                        anchors.centerIn: parent
                        text: homePage.username
                              ? homePage.username.charAt(0).toUpperCase() : '?'
                        fontSize: 'medium'
                        color: theme.palette.normal.baseText
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            var menu = PopupUtils.open(userMenuComponent, avatarCircle)
                            menu.username = homePage.username
                            menu.serverUrl = homePage.serverUrl
                            menu.openSettingsCallback = homePage.openSettingsCallback
                            menu.openAboutCallback = homePage.openAboutCallback
                        }
                    }
                }

                Label {
                    text: pageHeader.title
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    Component {
        id: userMenuComponent
        UserMenu {}
    }

    Flickable {
        id: homeFlickable
        anchors {
            top: pageHeader.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        contentWidth: width
        contentHeight: homeColumn.implicitHeight
        clip: true

        Column {
            id: homeColumn
            width: homeFlickable.width
            spacing: units.gu(2)

            OfflineBanner { id: offlineBanner }

            Repeater {
                id: sectionRepeater
                model: [
                    { title: i18n.tr('Recently played'),   functionName: 'bridge.getRecentAlbums' },
                    { title: i18n.tr('Favourites'),        functionName: 'bridge.getFavouriteAlbums' },
                    { title: i18n.tr('Frequently played'), functionName: 'bridge.getFrequentAlbums' },
                    { title: i18n.tr('Highest rated'),     functionName: 'bridge.getHighestAlbums' },
                    { title: i18n.tr('Newly added'),       functionName: 'bridge.getNewestAlbums' },
                    { title: i18n.tr('Random'),            functionName: 'bridge.getRandomAlbums' }
                ]
                delegate: homePage.albumRowDelegate
            }
        }
    }

    Component.onCompleted: {
        // Background auth: failure must not interrupt browsing.
        // Skip when the login flow just authenticated; reset the
        // flag so a later cold start still authenticates.
        if (mainView.justAuthenticated) {
            mainView.justAuthenticated = false
        } else {
            pythonBridge.call('bridge.authenticate', [], function(authResult) {
                if (authResult && !authResult.ok && authResult.errorKind === 'offline') {
                    offlineBanner.visible = true
                }
            })
        }
        pythonBridge.call('bridge.getUserInfo', [], function(userInfo) {
            if (userInfo && userInfo.ok) {
                homePage.username = userInfo.username
                homePage.serverUrl = userInfo.serverUrl
            }
        })
        // Fire all six fetches at once; each row renders as its
        // data arrives. Favourites answers from the local DB.
        for (var i = 0; i < sectionRepeater.model.length; i++) {
            loadRow(i, sectionRepeater.model[i].functionName)
        }
    }

    function loadRow(rowIndex, functionName) {
        pythonBridge.call(functionName, [], function(result) {
            if (result && result.ok) {
                var row = sectionRepeater.itemAt(rowIndex)
                for (var i = 0; i < result.albums.length; i++) {
                    row.model.append(result.albums[i])
                }
            } else if (result && result.errorKind === 'offline') {
                offlineBanner.visible = true
            }
            // Any other failure: the row stays empty and hidden.
        })
    }
}
