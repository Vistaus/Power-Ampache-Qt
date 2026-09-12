/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3

Page {
    property string message: i18n.tr('Could not open the local database')

    header: PageHeader {
        title: i18n.tr('Power Ampache')
    }

    Label {
        anchors.centerIn: parent
        text: message
    }
}
