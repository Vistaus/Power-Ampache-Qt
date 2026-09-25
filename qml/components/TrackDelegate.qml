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

    // Library songs list only: replaces the track-number column with
    // the song's album art and enriches the subtext with the album
    // name. Album/playlist hosts keep the number + artist row.
    property bool showArt: false

    height: units.gu(6)

    Item {
        id: leadingSlot
        anchors {
            left: parent.left
            leftMargin: units.gu(2)
            verticalCenter: parent.verticalCenter
        }
        width: showArt ? units.gu(4) : units.gu(3)
        height: units.gu(4)

        Label {
            id: trackNumberLabel
            anchors.centerIn: parent
            visible: !showArt
            text: modelData.trackNumber
        }

        Image {
            anchors.centerIn: parent
            width: units.gu(4)
            height: units.gu(4)
            visible: showArt
            source: modelData.hasArt
                    ? modelData.imageUrl
                    : Qt.resolvedUrl('../../assets/fallback/ic_speaker_colored_432px.svg')
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
    }

    Column {
        anchors {
            left: leadingSlot.right
            leftMargin: units.gu(1)
            right: durationLabel.left
            rightMargin: units.gu(1)
            verticalCenter: parent.verticalCenter
        }

        Label {
            width: parent.width
            text: modelData.title
            font.bold: true
            elide: Text.ElideRight
        }

        Label {
            width: parent.width
            text: showArt
                  ? modelData.artistName + ' - ' + modelData.albumName
                  : modelData.artistName
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
