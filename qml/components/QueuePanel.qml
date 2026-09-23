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
    property var overlayRoot

    // Pull-to-dismiss wiring: forward top-overshoot to the overlay
    // sheet (PlayerOverlay overscrollPull/Release/Retract). Dragging
    // down while already at the top drags the sheet instead; normal
    // scrolling is untouched.
    boundsBehavior: Flickable.DragAndOvershootBounds
    onContentYChanged: {
        if (!overlayRoot) {
            return
        }
        if (contentY < 0) {
            overlayRoot.overscrollPull(-contentY)
        } else {
            overlayRoot.overscrollRetract()
        }
    }
    onDraggingChanged: {
        if (!dragging && overlayRoot) {
            overlayRoot.overscrollRelease(contentY < 0 ? -contentY : 0)
        }
    }
    onMovementEnded: {
        // Safety net: if the dragging signal never fired (platform
        // quirk), the rebound's end still settles a followed sheet.
        if (overlayRoot && contentY >= 0) {
            overlayRoot.overscrollRelease(0)
        }
    }

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

        Item {
            id: queueArtSlot
            anchors {
                left: parent.left
                leftMargin: units.gu(2)
                verticalCenter: parent.verticalCenter
            }
            width: units.gu(4)
            height: units.gu(4)

            Image {
                anchors.centerIn: parent
                width: units.gu(4)
                height: units.gu(4)
                source: modelData.hasArt
                        ? modelData.imageUrl
                        : Qt.resolvedUrl('../../assets/fallback/ic_speaker_colored_432px.svg')
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
        }

        Column {
            anchors {
                left: queueArtSlot.right
                leftMargin: units.gu(1)
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
                text: modelData.artistName + ' - ' + modelData.albumName
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
