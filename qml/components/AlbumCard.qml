/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3

// One cover card in a horizontal home row. Delegate context provides
// the ListModel roles (id, name, artistName, artUrl).
// openAlbumCallback(albumId, albumName) is injected at the use site.
Item {
    id: albumCard

    property var openAlbumCallback

    width: units.gu(16)

    Rectangle {
        id: coverFrame
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: width
        color: theme.palette.normal.base

        Image {
            anchors.fill: parent
            source: artUrl
            visible: artUrl !== ''
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }

        Image {
            anchors.centerIn: parent
            width: units.gu(6)
            height: units.gu(6)
            source: Qt.resolvedUrl('../../assets/fallback/ic_speaker_colored_432px.svg')
            visible: artUrl === ''
            asynchronous: true
        }
    }

    Column {
        anchors {
            left: parent.left
            right: parent.right
            top: coverFrame.bottom
            topMargin: units.gu(0.5)
        }
        spacing: units.gu(0.2)

        Label {
            width: parent.width
            text: name
            fontSize: 'small'
            font.bold: true
            elide: Text.ElideRight
        }

        Label {
            width: parent.width
            text: artistName
            fontSize: 'small'
            elide: Text.ElideRight
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: openAlbumCallback(model.id, model.name)
    }
}
