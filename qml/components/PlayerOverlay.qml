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

    // Chevron hint for the MiniBar: pull up when closed, drag down
    // when open. Empty when the overlay is disabled (wide mode).
    readonly property string chevronIcon: {
        if (!enabled) {
            return ''
        }
        return overlayPanel.y < overlayPanel.height * 0.5 ? 'go-down' : 'go-up'
    }

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
        if (overlayHeader.sections.selectedIndex === 2) {
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
            + ' state=' + overlayPanel.state + ' chevron=' + chevronIcon)
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
        if (dragDirection === 'TopToBottom' && overlayPanel.state === "expanded") {
            collapse()
            return
        }
        if (overlayPanel.y < overlayPanel.height * 0.8) {
            open()
        } else {
            collapse()
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
        var hasLyrics = model.length > 2
        if (present === hasLyrics) {
            return
        }
        var selected = overlayHeader.sections.selectedIndex
        if (present) {
            overlayHeader.sections.model = [i18n.tr('Now Playing'), i18n.tr('Queue'), i18n.tr('Lyrics')]
        } else {
            overlayHeader.sections.model = [i18n.tr('Now Playing'), i18n.tr('Queue')]
            if (selected > 1) {
                selected = 0
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
                sections.model = [i18n.tr('Now Playing'), i18n.tr('Queue')]
            }
        }

        // Now Playing section (panel component unchanged; anchors and
        // visibility are set at this use site).
        NowPlayingPanel {
            id: nowPlayingPanel
            playback: overlayRoot.playback
            audioEngine: overlayRoot.audioEngine
            formatDuration: overlayRoot.formatDuration
            anchors {
                top: overlayHeader.bottom
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                // Legal anchor (parent); the bar strip is reserved
                // via margin bindings - anchors cannot cross subtrees.
                bottomMargin: (overlayRoot.miniBar !== null && overlayRoot.miniBar.visible
                               ? overlayRoot.miniBar.height : 0)
                              + (overlayRoot.navBar !== null && overlayRoot.navBar.visible
                                 ? overlayRoot.navBar.height : 0)
            }
            visible: overlayHeader.sections.selectedIndex === 0
        }

        // Queue section.
        QueuePanel {
            id: queuePanel
            playback: overlayRoot.playback
            anchors {
                top: overlayHeader.bottom
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                // Legal anchor (parent); the bar strip is reserved
                // via margin bindings - anchors cannot cross subtrees.
                bottomMargin: (overlayRoot.miniBar !== null && overlayRoot.miniBar.visible
                               ? overlayRoot.miniBar.height : 0)
                              + (overlayRoot.navBar !== null && overlayRoot.navBar.visible
                                 ? overlayRoot.navBar.height : 0)
            }
            visible: overlayHeader.sections.selectedIndex === 1
        }

        // Lyrics section.
        LyricsPanel {
            id: lyricsPanel
            anchors {
                top: overlayHeader.bottom
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                // Legal anchor (parent); the bar strip is reserved
                // via margin bindings - anchors cannot cross subtrees.
                bottomMargin: (overlayRoot.miniBar !== null && overlayRoot.miniBar.visible
                               ? overlayRoot.miniBar.height : 0)
                              + (overlayRoot.navBar !== null && overlayRoot.navBar.visible
                                 ? overlayRoot.navBar.height : 0)
            }
            visible: overlayHeader.sections.selectedIndex === 2
        }
    }

    Connections {
        target: overlayHeader.sections
        onSelectedIndexChanged: {
            if (overlayHeader.sections.selectedIndex === 2) {
                overlayRoot.loadLyrics()
            }
        }
    }

    Connections {
        target: playback
        onCurrentSongChanged: {
            // Visible-only lyrics reload: a collapsed overlay skips
            // the fetch; reopening refreshes via open().
            if (overlayHeader.sections.selectedIndex === 2
                    && overlayPanel.state === "expanded") {
                overlayRoot.loadLyrics()
            }
        }
    }
}
