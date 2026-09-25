/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3

// Shared loading/empty state for list and grid views. Shows a spinner
// while the owning view's fetch is in flight and its model is still
// empty, and a message once the fetch has settled with no rows.
// Invisible as soon as the model has content, so chunked load-more
// never flashes it. Declares NO geometry: the use site's anchors are
// the single definition (this Item also has no input handlers, so it
// never intercepts touches aimed at what is beneath it).
Item {
    id: viewState

    // True while the owning view's fetch is in flight.
    property bool busy: false
    // True when the owning view's model has no rows.
    property bool empty: false
    // Message shown when empty and not busy ('' hides the message).
    property string emptyMessage: ''

    visible: empty && (busy || emptyMessage !== '')

    ActivityIndicator {
        anchors.centerIn: parent
        running: viewState.busy
        visible: viewState.busy
    }

    Label {
        anchors.centerIn: parent
        visible: !viewState.busy && viewState.emptyMessage !== ''
        text: viewState.emptyMessage
        color: theme.palette.normal.baseText
    }
}
