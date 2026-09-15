/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3

// Queue panel: the play queue list; tap a row to jump to that
// position. playback (the queue manager) is injected at the use
// site; anchors and visibility are set there too.
ListView {
    id: queueListView

    property var playback

    clip: true
    model: playback.queue

    delegate: Item {
        width: queueListView.width
        height: units.gu(6)

        Rectangle {
            anchors.fill: parent
            color: index === playback.playerIndex
                   ? theme.palette.normal.base : 'transparent'
        }

        Column {
            anchors {
                left: parent.left
                leftMargin: units.gu(2)
                right: parent.right
                rightMargin: units.gu(2)
                verticalCenter: parent.verticalCenter
            }

            Label {
                width: parent.width
                text: modelData.title
                font.bold: index === playback.playerIndex
                elide: Text.ElideRight
            }

            Label {
                width: parent.width
                text: modelData.artistName
                fontSize: 'small'
                elide: Text.ElideRight
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                console.log('engine: queue tap index=' + index)
                playback.playFrom(playback.queue, index)
            }
        }
    }
}
