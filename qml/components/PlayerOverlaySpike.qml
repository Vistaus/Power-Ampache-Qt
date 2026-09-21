/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3

// SPIKE ONLY - throwaway probe for the player-overlay design, deleted
// after the verdict. Questions it answers:
// (1) does the toolkit BottomEdge work app-wide, above the APL?
// (2) does its gesture area steal taps from the NavBar/MiniBar/lists?
// (3) do commit()/collapse() work programmatically on this platform?
// NOT production UI. The real overlay (if this passes) hosts the
// existing player panels instead.
BottomEdge {
    id: bottomEdge
    objectName: 'playerOverlaySpike'

    // Sits above the APL, the MiniBar and the NavBar (last declared
    // child in Main.qml paints on top).
    anchors.fill: parent

    preloadContent: true

    // Injected at the use site; null keeps the spike inert.
    property var navBar: null

    contentComponent: Component {
        Rectangle {
            id: spikePanel
            color: theme.palette.normal.background
            width: bottomEdge.width
            height: bottomEdge.height

            Label {
                anchors.centerIn: parent
                text: 'Player overlay SPIKE - dummy content'
            }

            Label {
                anchors {
                    top: parent.top
                    right: parent.right
                    topMargin: units.gu(2)
                    rightMargin: units.gu(2)
                }
                text: 'X'
                fontSize: 'large'

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        console.log('playerOverlaySpike: X tapped, collapse()')
                        bottomEdge.collapse()
                    }
                }
            }
        }
    }

    // MiniBar tap entry: narrow -> commit the overlay; wide (or login)
    // -> the existing page-based player, unchanged.
    function openPlayer() {
        console.log('playerOverlaySpike: openPlayer enabled=' + enabled
            + ' status=' + status)
        if (!enabled) {
            if (navBar !== null) {
                navBar.openPlayer()
            }
            return
        }
        commit()
    }

    Component.onCompleted: {
        console.log('playerOverlaySpike: created')
        // The existing MiniBar is the visible handle; the toolkit's
        // chip hint stays hidden.
        hint.status = BottomEdgeHint.Hidden
    }

    onStatusChanged: {
        console.log('playerOverlaySpike: status=' + status
            + ' (0=Hidden 1=Revealed 2=Committed)')
        // The style re-asserts hint visibility on reveal; keep the
        // chip hidden and log whenever it reverts.
        if (hint.status !== BottomEdgeHint.Hidden) {
            console.log('playerOverlaySpike: hint went visible ('
                + hint.status + '), re-hiding')
            hint.status = BottomEdgeHint.Hidden
        }
    }

    onDragDirectionChanged: {
        console.log('playerOverlaySpike: dragDirection=' + dragDirection)
    }

    onCommitStarted: console.log('playerOverlaySpike: commitStarted')
    onCommitCompleted: console.log('playerOverlaySpike: commitCompleted')
    onCollapseStarted: console.log('playerOverlaySpike: collapseStarted')
    onCollapseCompleted: console.log('playerOverlaySpike: collapseCompleted')

    // Rotation safety: leaving single-column mode force-collapses so
    // the wide-mode page player owns the screen.
    onEnabledChanged: {
        if (!enabled && status !== BottomEdge.Hidden) {
            console.log('playerOverlaySpike: enabled=false while open, force collapse')
            collapse()
        }
    }
}
