/*
 * SPDX-FileCopyrightText: 2026 icefields
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3

// One-time welcome dialog. Self-contained: owns its content and its
// own dismissal. The opening page decides when to show it.
Dialog {
    id: welcomeDialog
    objectName: 'welcomeDialog'
    title: i18n.tr('Welcome to Power Ampache')

    Label {
        width: parent.width
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHLeft
        color: theme.palette.normal.baseText
        text: i18n.tr('Coming soon:')
    }
    Label {
        width: parent.width
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHLeft
        color: theme.palette.normal.baseText
        text: i18n.tr('● Star ratings for songs, albums and playlists') + '\n'
              + i18n.tr('● Playlist creation and editing') + '\n'
              + i18n.tr('● Per-song context menu')
    }
    Label {
        width: parent.width
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHLeft
        color: theme.palette.normal.baseText
        text: i18n.tr('Planned: downloads for offline listening.')
    }
    Label {
        width: parent.width
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHLeft
        color: theme.palette.normal.baseText
        text: i18n.tr('The app is under active development, with more features on the way. If you run into any issues, please report them and they will be addressed.')
    }

    Button {
        text: i18n.tr("Let's go")
        onClicked: PopupUtils.close(welcomeDialog)
    }
}
