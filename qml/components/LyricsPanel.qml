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
