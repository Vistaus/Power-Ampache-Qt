/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3
import QtGraphicalEffects 1.0
import Lomiri.Components.Popups 1.3
import Lomiri.Components.ListItems 1.3

// Account menu, opened from the Home header avatar. Header shows the
// user placeholder circle + username over the server address; items
// Settings / About report back via injected callbacks (assign on the
// instance AFTER PopupUtils.open — JS function refs do not survive
// creation-properties).
Popover {
    id: userMenu

    property string username: ''
    property string serverUrl: ''
    property string avatarArtUrl: ''
    property bool avatarHasArt: false
    property var openSettingsCallback: null
    property var openAboutCallback: null

    contentWidth: units.gu(30)

    Column {
        anchors { left: parent.left; right: parent.right }

        // Menu header: placeholder avatar + username + server address.
        Item {
            width: parent.width
            height: units.gu(8)

            Row {
                anchors {
                    left: parent.left
                    leftMargin: units.gu(1.5)
                    verticalCenter: parent.verticalCenter
                }
                spacing: units.gu(1.5)

                Item {
                    id: menuAvatar
                    width: units.gu(5)
                    height: units.gu(5)
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                        id: menuAvatarImage
                        anchors.fill: parent
                        visible: userMenu.avatarHasArt
                                  && userMenu.avatarArtUrl !== ''
                        source: visible ? userMenu.avatarArtUrl : ''
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }

                    OpacityMask {
                        anchors.fill: parent
                        visible: menuAvatarImage.visible
                        source: menuAvatarImage
                        maskSource: Rectangle {
                            width: menuAvatar.width
                            height: menuAvatar.height
                            radius: menuAvatar.width / 2
                            visible: false
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: theme.palette.normal.base
                        visible: !menuAvatarImage.visible

                        Label {
                            anchors.centerIn: parent
                            text: userMenu.username
                                  ? userMenu.username.charAt(0).toUpperCase()
                                  : '?'
                            fontSize: 'large'
                            color: theme.palette.normal.baseText
                        }
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: units.gu(0.5)

                    Label { text: userMenu.username }
                    Label {
                        text: userMenu.serverUrl
                        fontSize: 'small'
                        opacity: 0.7
                    }
                }
            }
        }

        ThinDivider {}

        Standard {
            text: i18n.tr('Settings')
            onClicked: {
                PopupUtils.close(userMenu)
                if (userMenu.openSettingsCallback) {
                    userMenu.openSettingsCallback()
                }
            }
        }

        Standard {
            text: i18n.tr('About')
            onClicked: {
                PopupUtils.close(userMenu)
                if (userMenu.openAboutCallback) {
                    userMenu.openAboutCallback()
                }
            }
        }
    }
}
