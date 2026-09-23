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
        { label: i18n.tr('High (320 kbps)'), value: 320 }
    ]
    property int currentBitrate: 320

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

    function doClearCache() {
        pythonBridge.call('bridge.clearCache', [], function(result) {
            if (result && result.ok) {
                loadCacheStats()
            } else if (result && !result.ok) {
                console.log('settings: clear failed: ' + result.message)
            }
        })
    }

    function formatBytes(bytes) {
        if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(1) + ' GB'
        if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + ' MB'
        if (bytes >= 1024) return (bytes / 1024).toFixed(1) + ' KB'
        return bytes + ' B'
    }

    function loadCacheStats() {
        pythonBridge.call('bridge.getCacheStats', [], function(result) {
            if (result && result.ok) {
                cacheStatsText = result.songs + ' ' + i18n.tr('songs')
                    + ' · ' + result.albums + ' ' + i18n.tr('albums')
                    + ' · ' + result.artists + ' ' + i18n.tr('artists')
                    + ' · ' + formatBytes(result.totalSize)
            } else {
                cacheStatsText = i18n.tr('Unavailable')
            }
        })
    }

    Component.onCompleted: {
        pythonBridge.call('bridge.getStreamingQuality', [], function(result) {
            if (result && result.ok) {
                currentBitrate = result.quality
            }
        })
        loadCacheStats()
    }
}
