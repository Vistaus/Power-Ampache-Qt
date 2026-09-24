/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3

// Like (flag) heart button, Canvas-painted: the '♥' text glyph falls
// back to the color emoji font on this platform and IGNORES the color
// property (always emoji-red, both states) - and the VS15
// text-presentation selector is not honored either (device-tested).
// A painted shape is deterministic and fully theme-controlled:
// unliked = baseText, liked = negative. Repaints on state change; a
// live theme switch re-paints on the next toggle.
Item {
    id: heartButton

    // State in: true = liked. The page owns the flag.
    property bool liked: false
    // Fired on tap; the page performs the bridge call that flips liked.
    signal toggled()

    width: units.gu(4)
    height: units.gu(4)

    Canvas {
        id: heartCanvas
        anchors.centerIn: parent
        width: units.gu(3)
        height: width
        antialiasing: true
        onPaint: {
            var ctx = getContext('2d')
            ctx.reset()
            ctx.fillStyle = heartButton.liked
                         ? theme.palette.normal.negative
                         : theme.palette.normal.baseText
            ctx.beginPath()
            // Two circles + a triangle: the classic geometric heart.
            var w = width
            var r = w / 4
            ctx.arc(w / 4, w / 4, r, 0, 2 * Math.PI)
            ctx.arc(3 * w / 4, w / 4, r, 0, 2 * Math.PI)
            ctx.moveTo(w / 2, w)
            ctx.lineTo(0, w / 2.6)
            ctx.lineTo(w, w / 2.6)
            ctx.closePath()
            ctx.fill()
        }
        Connections {
            target: heartButton
            onLikedChanged: heartCanvas.requestPaint()
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: heartButton.toggled()
    }
}
