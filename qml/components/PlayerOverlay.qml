/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3

// Always-alive player overlay for single-column mode: the MiniBar is
// the handle - tap toggles, drag makes the panel follow the finger,
// release past 20% commits, drag down closes. The panel slides UNDER
// the MiniBar/NavBar (declared before them in Main.qml), which stay
// visible and tappable, so the overlay needs no close button.
// Wide mode keeps the page-based player untouched: enabled=false
// hides the panel and tapAction() falls back to navBar.openPlayer().
// miniBar (content bottom anchor), navBar, playback, pythonBridge,
// audioEngine and formatDuration are injected at the use site.
Item {
    id: overlayRoot
    objectName: 'playerOverlay'
    // Full-screen root: the panel's geometry and the drag range all
    // derive from this Item's size. Anchored children cannot size
    // their parent (circular), so without this the Item stays 0x0 and
    // the overlay can never appear.
    anchors.fill: parent

    property var miniBar
    property var navBar
    property var playback
    property var pythonBridge
    property var audioEngine
    property var formatDuration

    // Drag/tap API consumed by MiniBar's handle MouseArea.
    readonly property alias dragTarget: overlayPanel
    readonly property real dragMaxY: overlayPanel.height

    // Release decision: fraction of the panel height the sheet must
    // travel for the release to commit the opposite state. 0.2 =
    // one fifth of the screen. Tuned on device.
    readonly property real releaseTravelFraction: 0.2

    // Pull-to-dismiss state for the scrollable sections (Queue/
    // Lyrics): see the overscroll* functions below the drag handle
    // callbacks. Threshold in gu - tune on device.
    property bool overscrollActive: false
    readonly property real overscrollThreshold: units.gu(6)

    function open() {
        if (!enabled) {
            return
        }
        overlayPanel.state = "expanded"
        console.log('playerOverlay: open')
        releaseAnimation.to = 0
        releaseAnimation.restart()
        // Refresh lyrics if the Lyrics section was left open: the
        // song may have changed while the overlay was collapsed.
        if (overlayHeader.sections.selectedIndex === 3) {
            loadLyrics()
        }
    }

    function collapse() {
        overlayPanel.state = "collapsed"
        console.log('playerOverlay: collapse')
        releaseAnimation.to = overlayPanel.height
        releaseAnimation.restart()
    }

    // MiniBar tap entry: toggle in single-column mode, page player
    // in wide mode / login.
    function tapAction() {
        console.log('playerOverlay: tapAction enabled=' + enabled
            + ' state=' + overlayPanel.state)
        if (!enabled) {
            if (navBar !== null) {
                navBar.openPlayer()
            }
            return
        }
        if (overlayPanel.state === "expanded") {
            collapse()
        } else {
            open()
        }
    }

    // MiniBar drag handle callbacks. handlePressed stops a mid-flight
    // release animation so the finger owns panel.y immediately.
    // handleReleased is direction-aware (Contacts semantics): ANY
    // downward drag from the open overlay closes; everything else
    // falls back to the 80% threshold. Pure taps stay no-ops here -
    // onClicked owns the toggle, real drags suppress it.
    function handlePressed() {
        if (!enabled) {
            return
        }
        console.log('playerOverlay: handlePressed y=' + overlayPanel.y
            + ' state=' + overlayPanel.state)
        releaseAnimation.stop()
    }

    function handleReleased(dragDirection) {
        if (!enabled) {
            return
        }
        console.log('playerOverlay: handleReleased direction=' + dragDirection
            + ' y=' + overlayPanel.y + ' state=' + overlayPanel.state)
        // Position-based release: where the sheet sits decides, the
        // sampled direction stays in the log only. Expanded: past
        // one fifth down = close, otherwise snap back open.
        // Collapsed: past one fifth up = open, otherwise fall back.
        if (overlayPanel.state === "expanded") {
            if (overlayPanel.y > dragMaxY * releaseTravelFraction) {
                collapse()
            } else {
                open()
            }
        } else {
            if (overlayPanel.y < dragMaxY * (1 - releaseTravelFraction)) {
                open()
            } else {
                collapse()
            }
        }
    }

    // --- Overscroll pull-to-dismiss (Queue/Lyrics sections) ---
    // The scrollable sections forward their top-overshoot here.
    // While the user drags down past the first row, the sheet tracks
    // the overshoot distance; on release, past the threshold = close,
    // otherwise snap home; dragging back up into the content
    // retracts. overscrollActive gates release/retract, and the
    // pull follow is skipped while releaseAnimation runs so the
    // Flickables' own rebound (which also produces negative
    // contentY) never fights the snap-home animation.
    function overscrollPull(offset) {
        if (!enabled || overlayPanel.state !== "expanded") {
            return
        }
        if (releaseAnimation.running) {
            return
        }
        releaseAnimation.stop()
        overscrollActive = true
        overlayPanel.y = Math.min(Math.max(0, offset), dragMaxY)
    }

    function overscrollRetract() {
        if (!overscrollActive) {
            return
        }
        overscrollActive = false
        console.log('playerOverlay: overscroll retract')
        releaseAnimation.to = 0
        releaseAnimation.restart()
    }

    function overscrollRelease(distance) {
        if (!overscrollActive) {
            return
        }
        overscrollActive = false
        console.log('playerOverlay: overscroll release distance=' + distance)
        if (distance > overscrollThreshold) {
            collapse()
        } else {
            releaseAnimation.to = 0
            releaseAnimation.restart()
        }
    }

    onEnabledChanged: {
        // Rotation/resize into wide mode: the overlay vanishes, the
        // music keeps playing (engine untouched) and the wide-mode
        // page player takes over. Collapse so a later shrink never
        // resurrects a half-open panel.
        if (!enabled && overlayPanel.state !== "collapsed") {
            console.log('playerOverlay: disabled while open, collapsing')
            overlayPanel.state = "collapsed"
        }
    }

    // Lyrics load lazily (PlayerPage semantics): only when the
    // Lyrics section opens, and again if the song changes while it
    // is showing AND the overlay is expanded.
    function loadLyrics() {
        if (playback.currentSong === null) {
            setLyricsSection(false)
            return
        }
        pythonBridge.call('bridge.getLyrics', [playback.currentSong.id], function(result) {
            if (result && result.ok && result.lyrics !== '') {
                lyricsPanel.lyricsText = result.lyrics
                setLyricsSection(true)
            } else {
                setLyricsSection(false)
            }
        })
    }

    // Add or remove the Lyrics section (PlayerPage logic verbatim,
    // ids requalified). Model changes reset selectedIndex, so
    // restore it afterwards and never leave it pointing past the end.
    function setLyricsSection(present) {
        var model = overlayHeader.sections.model
        var hasLyrics = model.length > 3
        if (present === hasLyrics) {
            return
        }
        var selected = overlayHeader.sections.selectedIndex
        if (present) {
            // Lyrics is the dynamic tail at index 3; adding it never
            // disturbs the static indices 0-2.
            overlayHeader.sections.model = [i18n.tr('Now Playing'), i18n.tr('Queue'), i18n.tr('Info'), i18n.tr('Lyrics')]
        } else {
            overlayHeader.sections.model = [i18n.tr('Now Playing'), i18n.tr('Queue'), i18n.tr('Info')]
            if (selected > 2) {
                // Was on Lyrics (3); land on Info (2), not root.
                selected = 2
            }
        }
        overlayHeader.sections.selectedIndex = selected
    }

    Rectangle {
        id: overlayPanel
        objectName: 'playerOverlayPanel'
        anchors {
            left: parent.left
            right: parent.right
        }
        height: parent.height
        y: height
        state: "collapsed"
        visible: overlayRoot.enabled && y < height
        color: theme.palette.normal.background

        // The ONE movement animation: open(), collapse() and the
        // drag-release threshold always restart it, so a release
        // after an imperative drag animates even when the semantic
        // state string does not change (same-state assignment would
        // be a no-op - the trap the deleted state machine had).
        NumberAnimation {
            id: releaseAnimation
            target: overlayPanel
            property: "y"
            duration: LomiriAnimation.FastDuration
            easing.type: Easing.Linear
        }
        onHeightChanged: {
            // Keep a collapsed panel glued to the bottom across
            // window resizes/rotations (imperative animation broke
            // the y binding).
            if (state === "collapsed" && !releaseAnimation.running) {
                y = height
            }
        }

        PageHeader {
            id: overlayHeader
            title: i18n.tr('Now Playing')
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
            }

            // Segmented control drives the three sections below
            // (PlayerPage semantics: sections is read-only, so
            // populate the model at completion).
            Component.onCompleted: {
                sections.model = [i18n.tr('Now Playing'), i18n.tr('Queue'), i18n.tr('Info')]
            }
        }

        // Now Playing section (panel component unchanged; anchors and
        // visibility are set at this use site).
        NowPlayingPanel {
            id: nowPlayingPanel
            playback: overlayRoot.playback
            audioEngine: overlayRoot.audioEngine
            formatDuration: overlayRoot.formatDuration
            overlayRoot: overlayRoot
            anchors {
                top: overlayHeader.bottom
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            visible: overlayHeader.sections.selectedIndex === 0
        }

        // Queue section.
        QueuePanel {
            id: queuePanel
            playback: overlayRoot.playback
            overlayRoot: overlayRoot
            anchors {
                top: overlayHeader.bottom
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            visible: overlayHeader.sections.selectedIndex === 1
        }

        // Lyrics section.
        LyricsPanel {
            id: lyricsPanel
            overlayRoot: overlayRoot
            anchors {
                top: overlayHeader.bottom
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            visible: overlayHeader.sections.selectedIndex === 3
        }

        // Song info section (static index 2; Lyrics is the dynamic
        // tail at index 3).
        SongInfoPanel {
            id: songInfoPanel
            playback: overlayRoot.playback
            pythonBridge: overlayRoot.pythonBridge
            formatDuration: overlayRoot.formatDuration
            overlayRoot: overlayRoot
            anchors {
                top: overlayHeader.bottom
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            visible: overlayHeader.sections.selectedIndex === 2
        }

        // Grabber: a transparent strip at the very top edge of the
        // sheet, pill only (no background). It overlays the header's
        // non-interactive title row; the sections control at the header's
        // bottom stays fully tappable. Tap = collapse, drag down =
        // dismiss.
        Rectangle {
            id: grabberStrip
            objectName: 'playerOverlayGrabber'
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            height: units.gu(4)
            color: 'transparent'

            // The classic bottom-sheet pill.
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: units.gu(12)
                height: units.gu(0.8)
                radius: height / 2
                color: theme.palette.normal.baseText
                opacity: 0.6
            }

            MouseArea {
                anchors.fill: parent
                property real previousY: -1
                property string dragDirection: 'None'
                drag {
                    axis: Drag.YAxis
                    target: overlayPanel
                    minimumY: 0
                    maximumY: overlayRoot.dragMaxY
                }
                onPressed: {
                    console.log('playerOverlay: grabber pressed y=' + mouse.y)
                    previousY = mouse.y
                    dragDirection = 'None'
                    overlayRoot.handlePressed()
                }
                onPositionChanged: {
                    // 2gu sampling (same as the mini bar handle).
                    if (previousY < 0) {
                        return
                    }
                    var yOffset = previousY - mouse.y
                    if (Math.abs(yOffset) <= units.gu(2)) {
                        return
                    }
                    previousY = mouse.y
                    dragDirection = yOffset > 0 ? 'BottomToTop' : 'TopToBottom'
                }
                onReleased: {
                    console.log('playerOverlay: grabber released direction=' + dragDirection)
                    overlayRoot.handleReleased(dragDirection)
                    previousY = -1
                    dragDirection = 'None'
                }
                onClicked: {
                    console.log('playerOverlay: grabber clicked (tap)')
                    overlayRoot.collapse()
                }
            }
        }
    }

    Connections {
        target: overlayHeader.sections
        onSelectedIndexChanged: {
            if (overlayHeader.sections.selectedIndex === 3) {
                overlayRoot.loadLyrics()
            }
        }
    }

    Connections {
        target: playback
        onCurrentSongChanged: {
            // Visible-only lyrics reload: a collapsed overlay skips
            // the fetch; reopening refreshes via open().
            if (overlayHeader.sections.selectedIndex === 3
                    && overlayPanel.state === "expanded") {
                overlayRoot.loadLyrics()
            }
        }
    }
}
