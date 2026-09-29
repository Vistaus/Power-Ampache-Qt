/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3
import QtGraphicalEffects 1.0
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
    property int pendingFetches: 0
    property bool homeSpinnerArmed: false
    // True only while a PULL-initiated refresh batch runs. PTR's
    // spinner binds here - never to the shared fetch counter, which
    // is also true during the initial load batch (the round-one bug
    // that painted a second spinner over the page on first load).
    property bool homeManualRefresh: false
    onPendingFetchesChanged: {
        if (pendingFetches > 0) {
            homeSpinnerArmed = false
            homeSpinnerTimer.restart()
        } else {
            homeSpinnerTimer.stop()
            homeSpinnerArmed = false
            // The last fetch of ANY batch lands here; a pull rode
            // this same counter, so this is what releases the PTR
            // spinner.
            homeManualRefresh = false
        }
    }
    Timer {
        id: homeSpinnerTimer
        interval: 1500
        onTriggered: homePage.homeSpinnerArmed = true
    }
    property string avatarArtUrl: ''
    property bool avatarHasArt: false

    header: PageHeader {
        id: pageHeader
        title: i18n.tr('Power Ampache')
        contents: Item {
            anchors.fill: parent

            Row {
                anchors {
                    left: parent.left
                    leftMargin: units.gu(0.25)
                    verticalCenter: parent.verticalCenter
                }
                spacing: units.gu(1.5)

                Item {
                    id: avatarCircle
                    width: units.gu(4)
                    height: units.gu(4)
                    anchors.verticalCenter: parent.verticalCenter

                    // Real avatar: circular crop via OpacityMask.
                    // Visible only when the server says art exists AND
                    // a URL came back - the art string alone is never
                    // proof (server placeholder URLs are unconditional).
                    Image {
                        id: avatarImage
                        // Never visible directly - the OpacityMask
                        // below is the ONLY renderer (a visible square
                        // Image leaks around the mask: the 1.0.57
                        // bug, render-proven).
                        anchors.fill: parent
                        visible: false
                        source: homePage.avatarHasArt
                                 && homePage.avatarArtUrl !== ''
                                ? homePage.avatarArtUrl : ''
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }

                    OpacityMask {
                        id: avatarMask
                        anchors.fill: parent
                        // The mask owns rendering: shown only when
                        // the account has art AND the image loaded.
                        visible: homePage.avatarHasArt
                                 && homePage.avatarArtUrl !== ''
                                 && avatarImage.status === Image.Ready
                        source: avatarImage
                        maskSource: Rectangle {
                            width: avatarCircle.width
                            height: avatarCircle.height
                            radius: avatarCircle.width / 2
                            visible: false
                        }
                    }

                    // Initials placeholder - the original look, shown
                    // whenever there is no real avatar.
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: theme.palette.normal.base
                        visible: !avatarMask.visible

                        Label {
                            anchors.centerIn: parent
                            text: homePage.username
                                  ? homePage.username.charAt(0).toUpperCase() : '?'
                            fontSize: 'medium'
                            color: theme.palette.normal.baseText
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            var menu = PopupUtils.open(userMenuComponent, avatarCircle)
                            menu.username = homePage.username
                            menu.serverUrl = homePage.serverUrl
                            menu.avatarArtUrl = homePage.avatarArtUrl
                            menu.avatarHasArt = homePage.avatarHasArt
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
            topMargin: units.gu(1)
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

        PullToRefresh {
            parent: homeFlickable
            refreshing: homePage.homeManualRefresh
            onRefresh: homePage.refreshHome()
        }
    }

    ActivityIndicator {
        anchors.centerIn: homeFlickable
        running: homePage.pendingFetches > 0 && homePage.homeSpinnerArmed
        visible: running
    }

    Component {
        id: welcomeDialogComponent
        WelcomeDialog { }
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
        pythonBridge.call('bridge.getUser', [], function(userResult) {
            if (userResult && userResult.ok) {
                homePage.username = userResult.username
                homePage.avatarArtUrl = userResult.artUrl || ''
                homePage.avatarHasArt = userResult.hasArt
            }
            // Offline or error: getUserInfo's values stand and the
            // avatar stays on the initials placeholder.
        })
        // Fire all six fetches at once; each row renders as its
        // data arrives. Favourites answers from the local DB.
        for (var i = 0; i < sectionRepeater.model.length; i++) {
            loadRow(i, sectionRepeater.model[i].functionName)
        }
        pythonBridge.call('bridge.getWelcomeShown', [], function(welcomeResult) {
            if (welcomeResult && welcomeResult.ok && !welcomeResult.shown) {
                // Set the flag BEFORE opening: even if the app dies
                // mid-display, the dialog never nags again.
                pythonBridge.call('bridge.setWelcomeShown', [], function() {})
                PopupUtils.open(welcomeDialogComponent, homePage)
            }
        })
    }

    function loadRow(rowIndex, functionName) {
        pendingFetches += 1
        pythonBridge.call(functionName, [], function(result) {
            pendingFetches -= 1
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

    function refreshHome() {
        // Pull-to-refresh: wipe the six row models and refetch. A
        // pull during an in-flight batch ADOPTS it - clearing models
        // while older responses are still landing would stack
        // duplicate appends. homeManualRefresh keeps the PTR spinner
        // up until the batch's last fetch lands (the counter watcher
        // resets it).
        homeManualRefresh = true
        if (homePage.pendingFetches > 0) return
        for (var i = 0; i < sectionRepeater.model.length; i++) {
            var row = sectionRepeater.itemAt(i)
            if (row) row.model.clear()
            loadRow(i, sectionRepeater.model[i].functionName)
        }
    }
}
