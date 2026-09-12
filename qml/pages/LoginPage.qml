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
            left: parent.left
            right: parent.right
            top: pageHeader.bottom
            margins: units.gu(4)
        }
        spacing: units.gu(2)

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
    }
}
