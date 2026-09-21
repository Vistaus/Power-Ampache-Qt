/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3

// Now-playing mini-bar: prev / play-pause / next; tapping the
// title/artist area opens the full player page.
// playback (the queue manager / playback engine object) and
// openPlayerCallback() are injected at the use site.
Rectangle {
    id: miniBar

    property var playback
    property var openPlayerCallback
    // Injected from Main.qml; null keeps the bar usable standalone.
    property var navBar: null
    // Player overlay handle wiring (single-column mode). null keeps
    // the bar standalone with tap-only behavior.
    property var overlayHandle: null
    property string chevronIconName: ''

    visible: playback.currentSong !== null
    anchors {
        left: parent.left
        right: parent.right
        // Sit directly above the nav bar when it is visible, above the
        // window bottom otherwise.
        bottom: (navBar !== null && navBar.visible) ? navBar.top : parent.bottom
    }
    height: units.gu(6)
    color: theme.palette.normal.base

    Column {
        id: miniBarText
        anchors {
            left: parent.left
            leftMargin: units.gu(2)
            right: miniBarControls.left
            rightMargin: units.gu(1)
            verticalCenter: parent.verticalCenter
        }

        Label {
            width: parent.width
            text: playback.currentSong !== null ? playback.currentSong.title : ''
            font.bold: true
            elide: Text.ElideRight
        }

        Label {
            width: parent.width
            text: playback.currentSong !== null ? playback.currentSong.artistName : ''
            fontSize: 'small'
            elide: Text.ElideRight
        }
    }

    // Grip affordance: chevron hinting the pull-up. Injected via
    // chevronIconName; empty string hides it. No MouseArea of its
    // own: taps fall through to the bar's drag/tap MouseArea below.
    Icon {
        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
        }
        width: units.gu(2)
        height: units.gu(1)
        name: miniBar.chevronIconName
        visible: miniBar.chevronIconName !== ''
        opacity: 0.5
    }

    // Tap target + drag handle: everything left of the controls.
    // Tap = openPlayerCallback (overlay toggle in single-column
    // mode, page player in wide mode). Drag = the panel follows the
    // finger via the injected overlayHandle; a real drag suppresses
    // onClicked, so tap and drag never double-fire. The enabled gate
    // on the drag target keeps a wide-mode drag from moving the
    // invisible panel.
    MouseArea {
        preventStealing: true
        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
            right: miniBarControls.left
        }
        drag {
            axis: Drag.YAxis
            target: miniBar.overlayHandle !== null && miniBar.overlayHandle.enabled
                    ? miniBar.overlayHandle.dragTarget : null
            minimumY: 0
            maximumY: miniBar.overlayHandle !== null && miniBar.overlayHandle.enabled
                      ? miniBar.overlayHandle.dragMaxY : 0
        }
        onPressed: {
            if (miniBar.overlayHandle !== null) {
                miniBar.overlayHandle.handlePressed()
            }
        }
        onReleased: {
            if (miniBar.overlayHandle !== null) {
                miniBar.overlayHandle.handleReleased()
            }
        }
        onClicked: openPlayerCallback()
    }

    Row {
        id: miniBarControls
        anchors {
            right: parent.right
            rightMargin: units.gu(2)
            verticalCenter: parent.verticalCenter
        }
        spacing: units.gu(2)

        Icon {
            width: units.gu(3)
            height: units.gu(3)
            name: 'media-skip-backward'

            MouseArea {
                anchors.fill: parent
                onClicked: playback.prev()
            }
        }

        Icon {
            width: units.gu(3)
            height: units.gu(3)
            name: playback.playing ? 'media-playback-pause' : 'media-playback-start'

            MouseArea {
                anchors.fill: parent
                onClicked: playback.togglePlayPause()
            }
        }

        Icon {
            width: units.gu(3)
            height: units.gu(3)
            name: 'media-skip-forward'

            MouseArea {
                anchors.fill: parent
                onClicked: playback.next()
            }
        }
    }
}
