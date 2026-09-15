/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3

// Library browser. The header's built-in Sections switch the body:
// Playlists is live content; Albums, Songs and Artists are labeled
// stubs until their content lands. pythonBridge (the Python element)
// and openPlaylistCallback(playlistId, playlistName) are injected at
// the use site.
Page {
    id: libraryPage
    objectName: 'libraryPage'

    property var pythonBridge
    property var openPlaylistCallback

    // Playlist dicts in the order the bridge returns them.
    property var playlists: []

    header: PageHeader {
        id: libraryHeader
        title: i18n.tr('Library')
        // sections is read-only: the model is assigned imperatively
        // in Component.onCompleted, never inline here.
    }

    ListView {
        id: playlistListView
        anchors {
            top: libraryHeader.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        visible: libraryHeader.sections.selectedIndex === 0
        clip: true
        model: libraryPage.playlists

        delegate: Item {
            id: playlistRow
            width: playlistListView.width
            height: units.gu(9)

            // Fixed square cover (same height:width idiom as the
            // album-row cards); LomiriShape supplies the rounded
            // corners. Whatever a server artUrl returns is shown
            // as-is - no blank-art detection.
            LomiriShape {
                id: coverShape
                anchors {
                    left: parent.left
                    leftMargin: units.gu(2)
                    verticalCenter: parent.verticalCenter
                }
                width: units.gu(7)
                height: width
                radius: 'small'
                backgroundColor: theme.palette.normal.base
                sourceFillMode: LomiriShape.PreserveAspectCrop
                source: Image {
                    source: modelData.artUrl || ''
                    asynchronous: true
                }

                Icon {
                    anchors.centerIn: parent
                    width: units.gu(3)
                    height: units.gu(3)
                    name: 'view-list-symbolic'
                    visible: !modelData.artUrl
                }
            }

            Column {
                anchors {
                    left: coverShape.right
                    leftMargin: units.gu(1.5)
                    right: parent.right
                    rightMargin: units.gu(2)
                    verticalCenter: parent.verticalCenter
                }
                spacing: units.gu(0.2)

                Label {
                    width: parent.width
                    text: modelData.name
                    fontSize: 'medium'
                    font.bold: true
                    elide: Text.ElideRight
                }

                Label {
                    width: parent.width
                    text: modelData.owner + ' - '
                          + (modelData.items === null ? 0 : modelData.items)
                          + ' ' + i18n.tr('tracks')
                    fontSize: 'small'
                    elide: Text.ElideRight
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: libraryPage.openPlaylistCallback(modelData.id, modelData.name)
            }
        }
    }

    Label {
        anchors {
            top: libraryHeader.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        visible: libraryHeader.sections.selectedIndex === 1
        text: i18n.tr('Albums')
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    Label {
        anchors {
            top: libraryHeader.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        visible: libraryHeader.sections.selectedIndex === 2
        text: i18n.tr('Songs')
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    Label {
        anchors {
            top: libraryHeader.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        visible: libraryHeader.sections.selectedIndex === 3
        text: i18n.tr('Artists')
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    Component.onCompleted: {
        // sections is read-only: populate the model imperatively.
        // Assigning the model resets selectedIndex, so the default
        // is set after it.
        libraryHeader.sections.model = [
            i18n.tr('Playlists'),
            i18n.tr('Albums'),
            i18n.tr('Songs'),
            i18n.tr('Artists')
        ]
        libraryHeader.sections.selectedIndex = 0
        pythonBridge.call('bridge.getPlaylists', [], function(result) {
            if (result && result.ok) {
                libraryPage.playlists = result.playlists
            }
            // On failure the page stays empty; session 3 owns error
            // surfacing.
        })
    }
}
