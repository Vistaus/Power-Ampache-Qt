/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3

Rectangle {
    visible: false
    width: parent.width
    height: units.gu(4)
    color: LomiriColors.orange

    Label {
        anchors.centerIn: parent
        text: i18n.tr('Offline - showing cached music')
    }
}
