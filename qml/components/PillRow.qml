/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3

// One horizontally scrollable row of rounded pill chips (genre /
// featured artist names). Visual only - browse-by-genre is a ROADMAP
// item. The model is a list of plain strings; pillColor distinguishes
// rows (darker pills for artists on the album page). Height collapses
// to 0 and the row hides itself when the model is empty.
Item {
    id: pillRow

    property var model: []
    property string pillColor: theme.palette.normal.base

    height: model.length > 0 ? units.gu(5) : 0
    visible: model.length > 0

    Flickable {
        anchors.fill: parent
        contentWidth: pillsRow.width + units.gu(4)
        contentHeight: height
        clip: true

        Row {
            id: pillsRow
            x: units.gu(2)
            anchors.verticalCenter: parent.verticalCenter
            spacing: units.gu(1)

            Repeater {
                model: pillRow.model

                delegate: Rectangle {
                    height: units.gu(4.5)
                    width: pillLabel.implicitWidth + units.gu(4.5)
                    radius: units.gu(1)
                    color: pillRow.pillColor

                    Label {
                        id: pillLabel
                        anchors.centerIn: parent
                        text: modelData
                        fontSize: 'medium'
                    }
                }
            }
        }
    }
}
