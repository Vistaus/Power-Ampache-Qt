/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.ListItems 1.3

// About: server + app info, license, source link. All values come from
// the bridge (SessionEntity + installed manifest) — nothing hardcoded.
Page {
    id: aboutPage

    property var pythonBridge

    header: PageHeader { id: pageHeader; title: i18n.tr('About') }

    property string appTitle: 'Power Ampache'
    property string appVersion: ''
    property string serverUrl: ''
    property string apiVersion: ''

    Flickable {
        id: aboutFlickable
        anchors {
            top: pageHeader.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        contentWidth: width
        contentHeight: aboutColumn.implicitHeight
        clip: true

        Column {
            id: aboutColumn
            width: aboutFlickable.width

            Header { text: i18n.tr('Server') }
            Subtitled { text: aboutPage.serverUrl; subText: i18n.tr('Server address') }
            Subtitled { text: aboutPage.appVersion; subText: i18n.tr('App version') }
            Subtitled { text: aboutPage.apiVersion; subText: i18n.tr('Ampache API version') }

            ThinDivider {}

            Header { text: i18n.tr('Support') }
            Item {
                width: parent.width
                height: units.gu(6)

                Image {
                    anchors {
                        left: parent.left
                        leftMargin: units.gu(2)
                        verticalCenter: parent.verticalCenter
                    }
                    width: units.gu(16)
                    height: units.gu(4.5)
                    fillMode: Image.PreserveAspectFit
                    source: Qt.resolvedUrl('../../assets/about/banner_patreon.png')
                    asynchronous: true
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: Qt.openUrlExternally('https://www.patreon.com/Icefields')
                }
            }
            Item {
                width: parent.width
                height: units.gu(6)

                Image {
                    anchors {
                        left: parent.left
                        leftMargin: units.gu(2)
                        verticalCenter: parent.verticalCenter
                    }
                    width: units.gu(16)
                    height: units.gu(4.5)
                    fillMode: Image.PreserveAspectFit
                    source: Qt.resolvedUrl('../../assets/about/bmc-brand-logo-button.png')
                    asynchronous: true
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: Qt.openUrlExternally('https://buymeacoffee.com/powerampache')
                }
            }
            Item {
                width: parent.width
                height: units.gu(6)

                Image {
                    anchors {
                        left: parent.left
                        leftMargin: units.gu(2)
                        verticalCenter: parent.verticalCenter
                    }
                    width: units.gu(16)
                    height: units.gu(4.5)
                    fillMode: Image.PreserveAspectFit
                    source: Qt.resolvedUrl('../../assets/about/paypal.png')
                    asynchronous: true
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: Qt.openUrlExternally('https://paypal.me/powerampache')
                }
            }

            ThinDivider {}

            Header { text: i18n.tr('Links') }
            Item {
                width: parent.width
                height: units.gu(6)

                Row {
                    anchors {
                        left: parent.left
                        leftMargin: units.gu(2)
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: units.gu(1.5)

                    Image {
                        width: units.gu(2.5)
                        height: units.gu(2.5)
                        anchors.verticalCenter: parent.verticalCenter
                        source: Qt.resolvedUrl('../../assets/about/matrix.png')
                        asynchronous: true
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: i18n.tr('Matrix Space')
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: Qt.openUrlExternally('https://matrix.to/#/%23power-ampache:matrix.org')
                }
            }
            Item {
                width: parent.width
                height: units.gu(6)

                Row {
                    anchors {
                        left: parent.left
                        leftMargin: units.gu(2)
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: units.gu(1.5)

                    Image {
                        width: units.gu(2.5)
                        height: units.gu(2.5)
                        anchors.verticalCenter: parent.verticalCenter
                        source: Qt.resolvedUrl('../../assets/about/ic_telegram.svg')
                        asynchronous: true
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: i18n.tr('Telegram')
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: Qt.openUrlExternally('https://t.me/PowerAmpache')
                }
            }
            Item {
                width: parent.width
                height: units.gu(6)

                Row {
                    anchors {
                        left: parent.left
                        leftMargin: units.gu(2)
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: units.gu(1.5)

                    Image {
                        width: units.gu(2.5)
                        height: units.gu(2.5)
                        anchors.verticalCenter: parent.verticalCenter
                        source: Qt.resolvedUrl('../../assets/about/ic_telegram.svg')
                        asynchronous: true
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: i18n.tr('Telegram chat')
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: Qt.openUrlExternally('https://t.me/PowerAmpache2')
                }
            }
            Item {
                width: parent.width
                height: units.gu(6)

                Row {
                    anchors {
                        left: parent.left
                        leftMargin: units.gu(2)
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: units.gu(1.5)

                    Image {
                        width: units.gu(2.5)
                        height: units.gu(2.5)
                        anchors.verticalCenter: parent.verticalCenter
                        source: Qt.resolvedUrl('../../assets/about/ic_mastodon.svg')
                        asynchronous: true
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: i18n.tr('Mastodon')
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: Qt.openUrlExternally('https://floss.social/@powerampache')
                }
            }
            Item {
                width: parent.width
                height: units.gu(6)

                Row {
                    anchors {
                        left: parent.left
                        leftMargin: units.gu(2)
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: units.gu(1.5)

                    Image {
                        width: units.gu(2.5)
                        height: units.gu(2.5)
                        anchors.verticalCenter: parent.verticalCenter
                        source: Qt.resolvedUrl('../../assets/about/ic_git.svg')
                        asynchronous: true
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: i18n.tr('Source code (GitHub)')
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: Qt.openUrlExternally('https://github.com/icefields/Power-Ampache-Qt')
                }
            }

            ThinDivider {}

            Header { text: i18n.tr('License') }
            Item {
                width: parent.width
                height: units.gu(9)

                Image {
                    anchors {
                        left: parent.left
                        leftMargin: units.gu(2)
                        verticalCenter: parent.verticalCenter
                    }
                    width: units.gu(10)
                    height: units.gu(6)
                    fillMode: Image.PreserveAspectFit
                    source: Qt.resolvedUrl('../../assets/about/gplv3.png')
                    asynchronous: true
                }
            }
            Subtitled {
                text: i18n.tr('GPL-3.0-only')
                subText: i18n.tr('Free as in Freedom')
            }
        }
    }

    Component.onCompleted: {
        pythonBridge.call('bridge.getUserInfo', [], function(result) {
            if (result && result.ok) aboutPage.serverUrl = result.serverUrl
        })
        pythonBridge.call('bridge.getServerInfo', [], function(result) {
            if (result && result.ok) aboutPage.apiVersion = result.api
        })
        pythonBridge.call('bridge.getAppInfo', [], function(result) {
            if (result && result.ok) {
                aboutPage.appTitle = result.title
                aboutPage.appVersion = result.version
            }
        })
    }
}
