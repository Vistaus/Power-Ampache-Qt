/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3

// Lyrics panel: the cached lyrics text for the current song. The
// page writes lyricsText from loadLyrics(); anchors and visibility
// are set at the use site.
Flickable {
    id: lyricsFlickable

    property alias lyricsText: lyricsLabel.text
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

    contentWidth: width
    contentHeight: lyricsLabel.height + units.gu(4)
    clip: true

    Label {
        id: lyricsLabel
        x: units.gu(2)
        y: units.gu(2)
        width: lyricsFlickable.width - units.gu(4)
        wrapMode: Text.Wrap
    }
}
