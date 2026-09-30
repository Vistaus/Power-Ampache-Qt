/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3

// Setup screen shown only when no credentials are stored. The
// pythonBridge object (the Python element) and authenticatedCallback()
// are injected at the use site;
// the callback performs the root-level actions after a successful
// authenticate (flag, clear stack, push home).
Page {
    id: loginPage

    property var pythonBridge
    property var authenticatedCallback

    header: PageHeader {
        id: pageHeader
        title: i18n.tr('Power Ampache')
    }

    Column {
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: pageHeader.bottom
            topMargin: units.gu(4)
        }
        // Caps at 40gu and centers on wide desktop windows; on a 45gu
        // phone page Math.min(45-8, 40) = 37gu, identical to the old
        // full-width-minus-4gu-margins rendering.
        width: Math.min(parent.width - units.gu(8), units.gu(40))
        spacing: units.gu(2)

        Image {
            width: units.gu(14)
            height: units.gu(14)
            anchors.horizontalCenter: parent.horizontalCenter
            source: Qt.resolvedUrl('../../assets/logo.svg')
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: i18n.tr('POWER AMPACHE')
            fontSize: 'large'
            font.bold: true
        }

        Label {
            width: parent.width
            text: i18n.tr('Connect to your Ampache server')
        }

        TextField {
            id: serverField
            width: parent.width
            placeholderText: i18n.tr('Server URL')
            inputMethodHints: Qt.ImhUrlCharactersOnly
        }

        TextField {
            id: usernameField
            width: parent.width
            placeholderText: i18n.tr('Username')
        }

        TextField {
            id: passwordField
            width: parent.width
            placeholderText: i18n.tr('Password')
            echoMode: TextInput.Password
        }

        Label {
            id: loginErrorLabel
            width: parent.width
            visible: text !== ''
            wrapMode: Text.Wrap
            color: LomiriColors.red
        }

        Button {
            id: connectButton
            width: parent.width
            color: LomiriColors.green
            text: i18n.tr('Connect')

            onClicked: {
                loginErrorLabel.text = ''
                connectButton.enabled = false
                pythonBridge.call('bridge.storeCredentials',
                        [serverField.text, usernameField.text, passwordField.text],
                        function(storeResult) {
                    if (!storeResult || !storeResult.ok) {
                        connectButton.enabled = true
                        loginErrorLabel.text = i18n.tr('Could not save credentials')
                        return
                    }
                    pythonBridge.call('bridge.authenticate', [], function(authResult) {
                        connectButton.enabled = true
                        if (authResult && authResult.ok) {
                            passwordField.text = ''
                            loginPage.authenticatedCallback()
                        } else if (authResult && authResult.errorKind === 'credentials') {
                            loginErrorLabel.text = i18n.tr('Wrong username or password')
                        } else if (authResult && authResult.errorKind === 'offline') {
                            loginErrorLabel.text = i18n.tr('Server unreachable')
                        } else {
                            loginErrorLabel.text = i18n.tr('Connection failed')
                        }
                    })
                })
            }
        }

        Label {
            width: parent.width
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            fontSize: 'small'
            color: theme.palette.normal.secondaryText
            text: i18n.tr('Nextcloud Music users: go to the Music app in your Nextcloud > Settings > Ampache and Subsonic, and create your Ampache credentials. The server URL is shown on the same page.')
        }
    }
}
