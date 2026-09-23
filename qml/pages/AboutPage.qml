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
            Standard {
                text: i18n.tr('Patreon')
                onClicked: Qt.openUrlExternally('https://www.patreon.com/Icefields')
            }
            Standard {
                text: i18n.tr('Buy Me a Coffee')
                onClicked: Qt.openUrlExternally('https://buymeacoffee.com/powerampache')
            }
            Standard {
                text: i18n.tr('PayPal')
                onClicked: Qt.openUrlExternally('https://paypal.me/powerampache')
            }

            ThinDivider {}

            Header { text: i18n.tr('Links') }
            Standard {
                text: i18n.tr('Matrix Space')
                onClicked: Qt.openUrlExternally('https://matrix.to/#/%23power-ampache:matrix.org')
            }
            Standard {
                text: i18n.tr('Telegram (announcements)')
                onClicked: Qt.openUrlExternally('https://t.me/PowerAmpache')
            }
            Standard {
                text: i18n.tr('Telegram chat')
                onClicked: Qt.openUrlExternally('https://t.me/PowerAmpache2')
            }
            Standard {
                text: i18n.tr('Mastodon')
                onClicked: Qt.openUrlExternally('https://floss.social/@powerampache')
            }
            Standard {
                text: i18n.tr('Source code (GitHub)')
                onClicked: Qt.openUrlExternally('https://github.com/icefields/Power-Ampache-Qt')
            }

            ThinDivider {}

            Header { text: i18n.tr('License') }
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
