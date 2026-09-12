/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3

// Now-playing mini-bar: prev / play-pause / next; tapping the
// title/artist area opens the full player page.
// queueManager (the playback engine object) and openPlayerCallback()
// are injected at the use site.
Rectangle {
    id: miniBar

    property var queueManager
    property var openPlayerCallback

    visible: queueManager.currentSong !== null
    anchors {
        left: parent.left
        right: parent.right
        bottom: parent.bottom
    }
    height: units.gu(6)
    color: theme.palette.normal.base

    Column {
        id: miniBarText
        anchors {
            left: parent.left
            leftMargin: units.gu(2)
            right: miniBarControls.left
            rightMargin: units.gu(1)
            verticalCenter: parent.verticalCenter
        }

        Label {
            width: parent.width
            text: queueManager.currentSong !== null ? queueManager.currentSong.title : ''
            font.bold: true
            elide: Text.ElideRight
        }

        Label {
            width: parent.width
            text: queueManager.currentSong !== null ? queueManager.currentSong.artistName : ''
            fontSize: 'small'
            elide: Text.ElideRight
        }
    }

    // Tap target that opens the player page: everything left of the
    // controls.
    MouseArea {
        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
            right: miniBarControls.left
        }
        onClicked: openPlayerCallback()
    }

    Row {
        id: miniBarControls
        anchors {
            right: parent.right
            rightMargin: units.gu(2)
            verticalCenter: parent.verticalCenter
        }
        spacing: units.gu(2)

        Icon {
            width: units.gu(3)
            height: units.gu(3)
            name: 'media-skip-backward'

            MouseArea {
                anchors.fill: parent
                onClicked: queueManager.prev()
            }
        }

        Icon {
            width: units.gu(3)
            height: units.gu(3)
            name: queueManager.playing ? 'media-playback-pause' : 'media-playback-start'

            MouseArea {
                anchors.fill: parent
                onClicked: queueManager.togglePlayPause()
            }
        }

        Icon {
            width: units.gu(3)
            height: units.gu(3)
            name: 'media-skip-forward'

            MouseArea {
                anchors.fill: parent
                onClicked: queueManager.next()
            }
        }
    }
}
