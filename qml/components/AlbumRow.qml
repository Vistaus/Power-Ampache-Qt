/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3

// One horizontal album row on the home page: section label plus a
// horizontal ListView of AlbumCards. Repeater delegate context provides
// modelData (the section dict with title). AlbumCard resolves via the
// implicit same-directory import. The property alias MUST keep the
// name "model": the home page calls row.model.append(...) on it.
// openAlbumCallback(albumId, albumName) is injected at the use site.
Item {
    id: albumRow

    property alias model: albumModel
    property var openAlbumCallback

    // Empty rows are omitted: the Column skips invisible children.
    visible: albumModel.count > 0
    width: parent.width
    height: rowLabel.height + albumListView.height + units.gu(1)

    ListModel {
        id: albumModel
    }

    Label {
        id: rowLabel
        anchors {
            left: parent.left
            top: parent.top
            leftMargin: units.gu(2)
        }
        text: modelData.title
        fontSize: 'large'
    }

    ListView {
        id: albumListView
        anchors {
            left: parent.left
            right: parent.right
            top: rowLabel.bottom
            topMargin: units.gu(1)
            leftMargin: units.gu(2)
        }
        height: units.gu(22)
        orientation: ListView.Horizontal
        spacing: units.gu(1)
        clip: true
        model: albumModel

        delegate: AlbumCard {
            height: albumListView.height
            openAlbumCallback: albumRow.openAlbumCallback
        }
    }
}
