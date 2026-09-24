/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3

// Like (flag) heart button, image-based: text glyphs and Canvas paint
// both failed on this platform (emoji fallback ignores color; painted
// path was defective). Two pre-colored SVGs, one per state - the
// source swap IS the state change. Unliked = gray outline,
// liked = solid red.
Item {
    id: heartButton

    // State in: true = liked. The page owns the flag.
    property bool liked: false
    // Fired on tap; the page performs the bridge call that flips liked.
    signal toggled()

    width: units.gu(4)
    height: units.gu(4)

    Image {
        anchors.centerIn: parent
        width: units.gu(3)
        height: width
        source: heartButton.liked
                ? Qt.resolvedUrl('../../assets/icons/heart-liked.svg')
                : Qt.resolvedUrl('../../assets/icons/heart-unliked.svg')
        asynchronous: true
    }

    MouseArea {
        anchors.fill: parent
        onClicked: heartButton.toggled()
    }
}
