/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import Lomiri.Components.ListItems 1.3
import "../components"

// Settings: streaming bitrate (persisted in LocalSettingsEntity, read
// by the bridge on every stream URL build), cache stats + clear
// (data tables only — credentials/session rows share the same DB file
// and MUST survive), and logout at the bottom (destroys credentials +
// session, returns to the login screen via the injected callback).
Page {
    id: settingsPage

    property var pythonBridge
    property var logoutCallback: null

    property var bitrateModel: [
        { label: i18n.tr('Low (96 kbps)'), value: 96 },
        { label: i18n.tr('Medium (192 kbps)'), value: 192 },
        { label: i18n.tr('High (320 kbps)'), value: 320 },
        { label: i18n.tr('Lossless (original)'), value: 0 }
    ]
    property int currentBitrate: 0
    // Theme: applied LIVE via Theme.name; 'system' = platform default
    // (phone-only semantics; desktop has no platform theme).
    property string currentTheme: ''
    property string currentScale: '1'
    function themeName(value) {
        if (value === 'dark') {
            return 'Lomiri.Components.Themes.SuruDark'
        }
        if (value === 'light') {
            return 'Lomiri.Components.Themes.Ambiance'
        }
        return ''
    }
    property bool artworkSwitchReady: false

    header: PageHeader { id: pageHeader; title: i18n.tr('Settings') }

    Flickable {
        id: settingsFlickable
        anchors {
            top: pageHeader.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        contentWidth: width
        contentHeight: settingsColumn.implicitHeight
        clip: true

        Column {
            id: settingsColumn
            width: settingsFlickable.width

            Header { text: i18n.tr('Theme') }

            Repeater {
                model: [
                    { label: i18n.tr('Dark'), value: 'dark' },
                    { label: i18n.tr('Light'), value: 'light' },
                    { label: i18n.tr('System (phone)'), value: 'system' }
                ]

                delegate: Standard {
                    text: modelData.label
                    onClicked: {
                        settingsPage.currentTheme = modelData.value
                        // Live apply; 'system' stays on the platform
                        // default (empty name = no Theme.name write).
                        var mapped = settingsPage.themeName(modelData.value)
                        if (mapped !== '') {
                            Theme.name = mapped
                        }
                        console.log('settings: theme live apply='
                                    + modelData.value
                                    + ' Theme.name=' + Theme.name)
                        settingsPage.pythonBridge.call(
                            'bridge.setThemeSetting',
                            [modelData.value],
                            function(result) {
                                if (!result || !result.ok) {
                                    console.log('settings: theme save failed: '
                                                + (result ? result.message : 'null'))
                                }
                            })
                    }

                    Rectangle {
                        anchors {
                            right: parent.right
                            rightMargin: units.gu(2)
                            verticalCenter: parent.verticalCenter
                        }
                        width: units.gu(1.5)
                        height: units.gu(1.5)
                        radius: width / 2
                        visible: settingsPage.currentTheme === modelData.value
                        color: theme.palette.normal.baseText
                    }
                }
            }

            Header { text: i18n.tr('UI Scale (desktop only)') }

            Repeater {
                model: [
                    { label: i18n.tr('100%'), value: '1' },
                    { label: i18n.tr('150%'), value: '1.5' },
                    { label: i18n.tr('170%'), value: '1.7' },
                    { label: i18n.tr('200%'), value: '2' }
                ]
                delegate: Standard {
                    text: modelData.label
                    onClicked: {
                        settingsPage.currentScale = modelData.value
                        settingsPage.pythonBridge.call(
                            'bridge.setScaleSetting',
                            [modelData.value],
                            function(result) {
                                if (result && result.ok) {
                                    PopupUtils.open(scaleRestartDialogComponent)
                                } else {
                                    console.log('settings: scale save failed: '
                                                + (result ? result.message : 'null'))
                                }
                            })
                    }
                    Rectangle {
                        anchors {
                            right: parent.right
                            rightMargin: units.gu(2)
                            verticalCenter: parent.verticalCenter
                        }
                        width: units.gu(1.5)
                        height: units.gu(1.5)
                        radius: width / 2
                        visible: settingsPage.currentScale === modelData.value
                        color: theme.palette.normal.baseText
                    }
                }
            }

            Header { text: i18n.tr('Streaming') }

            Repeater {
                model: settingsPage.bitrateModel

                delegate: Standard {
                    text: modelData.label
                    onClicked: {
                        settingsPage.currentBitrate = modelData.value
                        settingsPage.pythonBridge.call(
                            'bridge.setStreamingQuality',
                            [modelData.value],
                            function(result) {
                                if (!result || !result.ok) {
                                    console.log('settings: save failed: '
                                                + (result ? result.message : 'null'))
                                }
                            })
                    }

                    Rectangle {
                        anchors {
                            right: parent.right
                            rightMargin: units.gu(2)
                            verticalCenter: parent.verticalCenter
                        }
                        width: units.gu(1.5)
                        height: units.gu(1.5)
                        radius: width / 2
                        visible: settingsPage.currentBitrate === modelData.value
                        color: theme.palette.normal.baseText
                    }
                }
            }

            Header { text: i18n.tr('Artwork') }

            Item {
                width: parent.width
                height: units.gu(8)

                Column {
                    anchors {
                        left: parent.left
                        leftMargin: units.gu(2)
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: units.gu(0.5)

                    Label { text: i18n.tr('Use server placeholder art') }
                    Label {
                        text: i18n.tr('Switch on if your server provides a custom placeholder art')
                        fontSize: 'small'
                        opacity: 0.7
                    }
                }

                Switch {
                    id: serverPlaceholderSwitch
                    anchors {
                        right: parent.right
                        rightMargin: units.gu(2)
                        verticalCenter: parent.verticalCenter
                    }
                    onCheckedChanged: {
                        // Load-time assignment must not fire a save;
                        // the ready gate separates load from user taps.
                        if (settingsPage.artworkSwitchReady) {
                            settingsPage.pythonBridge.call(
                                'bridge.setServerPlaceholderSetting',
                                [checked], function(result) {
                                    if (!result || !result.ok) {
                                        console.log('settings: save failed: '
                                                    + (result ? result.message : 'null'))
                                    }
                                })
                        }
                    }
                }
            }

            Header { text: i18n.tr('Cache') }

            Subtitled {
                text: i18n.tr('Cached library')
                subText: settingsPage.cacheStatsText
            }

            Standard {
                text: i18n.tr('Clear cache')
                onClicked: PopupUtils.open(clearConfirmComponent)
            }

            Item { width: parent.width; height: units.gu(2) }

            Standard {
                text: i18n.tr('Log out')
                onClicked: {
                    settingsPage.pythonBridge.call('bridge.logout', [], function(result) {
                        if (result && result.ok && settingsPage.logoutCallback) {
                            settingsPage.logoutCallback()
                        } else if (result && !result.ok) {
                            console.log('settings: logout failed: ' + result.message)
                        }
                    })
                }
            }

            Item { width: parent.width; height: units.gu(2) }
        }
    }

    property string cacheStatsText: i18n.tr('Counting…')

    Component {
        id: clearConfirmComponent
        Dialog {
            id: clearConfirmDialog
            title: i18n.tr('Clear cache')
            text: i18n.tr('Removes all cached music data. Your login and settings are kept.')
            Button {
                text: i18n.tr('Clear')
                color: theme.palette.normal.negative
                onClicked: {
                    PopupUtils.close(clearConfirmDialog)
                    settingsPage.doClearCache()
                }
            }
            Button {
                text: i18n.tr('Cancel')
                onClicked: PopupUtils.close(clearConfirmDialog)
            }
        }
    }

    Component {
        id: scaleRestartDialogComponent
        Dialog {
            id: scaleRestartDialog
            title: i18n.tr('Restart required')
            text: i18n.tr('Restart the app to apply the new UI scale.')
            Button {
                text: i18n.tr('OK')
                onClicked: PopupUtils.close(scaleRestartDialog)
            }
        }
    }

    function doClearCache() {
        pythonBridge.call('bridge.clearCache', [], function(result) {
            if (result && result.ok) {
                loadCacheStats()
            } else if (result && !result.ok) {
                console.log('settings: clear failed: ' + result.message)
            }
        })
    }

    function loadCacheStats() {
        pythonBridge.call('bridge.getCacheStats', [], function(result) {
            if (result && result.ok) {
                cacheStatsText = result.songs + ' ' + i18n.tr('songs')
                    + ' · ' + result.albums + ' ' + i18n.tr('albums')
                    + ' · ' + result.artists + ' ' + i18n.tr('artists')
            } else {
                cacheStatsText = i18n.tr('Unavailable')
            }
        })
    }

    Component.onCompleted: {
        pythonBridge.call('bridge.getThemeSetting', [], function(result) {
            if (result && result.ok) {
                settingsPage.currentTheme = result.theme
            }
        })
        pythonBridge.call('bridge.getScaleSetting', [], function(result) {
            if (result && result.ok) {
                settingsPage.currentScale = result.scale
            }
        })
        pythonBridge.call('bridge.getStreamingQuality', [], function(result) {
            if (result && result.ok) {
                currentBitrate = result.quality
            }
        })
        pythonBridge.call('bridge.getServerPlaceholderSetting', [], function(result) {
            if (result && result.ok) {
                serverPlaceholderSwitch.checked = result.enabled
                settingsPage.artworkSwitchReady = true
            }
        })
        loadCacheStats()
    }
}
