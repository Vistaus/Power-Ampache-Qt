/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3

// One track row in the album page. Delegate context provides modelData
// (song dict) and index. playTrackCallback(rowIndex) and
// formatDuration(seconds) are injected at the use site.
Item {
    id: trackDelegate

    property var playTrackCallback
    property var formatDuration

    height: units.gu(6)

    Label {
        id: trackNumberLabel
        anchors {
            left: parent.left
            leftMargin: units.gu(2)
            verticalCenter: parent.verticalCenter
        }
        width: units.gu(3)
        text: modelData.trackNumber
    }

    Column {
        anchors {
            left: trackNumberLabel.right
            leftMargin: units.gu(1)
            right: durationLabel.left
            rightMargin: units.gu(1)
            verticalCenter: parent.verticalCenter
        }

        Label {
            width: parent.width
            text: modelData.title
            elide: Text.ElideRight
        }

        Label {
            width: parent.width
            text: modelData.artistName
            fontSize: 'small'
            elide: Text.ElideRight
        }
    }

    Label {
        id: durationLabel
        anchors {
            right: parent.right
            rightMargin: units.gu(2)
            verticalCenter: parent.verticalCenter
        }
        text: formatDuration(modelData.time)
        fontSize: 'small'
    }

    MouseArea {
        anchors.fill: parent
        onClicked: playTrackCallback(index)
    }
}
