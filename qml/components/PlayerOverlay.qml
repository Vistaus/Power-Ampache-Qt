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
    // True while the handle is pressed; drives the floating state so
    // the drag owns panel.y without fighting the animations.
    property bool dragging: false

    // Chevron hint for the MiniBar: pull up when closed, drag down
    // when open. Empty when the overlay is disabled (wide mode).
    readonly property string chevronIcon: {
        if (!enabled) {
            return ''
        }
        return overlayPanel.y < overlayPanel.height * 0.5 ? 'down' : 'up'
    }

    function open() {
        if (!enabled) {
            return
        }
        overlayPanel.state = "expanded"
        // Refresh lyrics if the Lyrics section was left open: the
        // song may have changed while the overlay was collapsed.
        if (overlayHeader.sections.selectedIndex === 2) {
            loadLyrics()
        }
    }

    function collapse() {
        overlayPanel.state = "collapsed"
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

    // MiniBar drag handle callbacks.
    function handlePressed() {
        if (!enabled) {
            return
        }
        dragging = true
    }

    function handleReleased() {
        if (!enabled) {
            dragging = false
            return
        }
        dragging = false
        // 20% release threshold (Contacts pattern): past it the
        // panel commits open, otherwise it snaps home.
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

        states: [
            State {
                name: "collapsed"
                PropertyChanges { target: overlayPanel; y: overlayPanel.height }
            },
            State {
                name: "expanded"
                PropertyChanges { target: overlayPanel; y: 0 }
            },
            State {
                name: "floating"
                when: overlayRoot.dragging
            }
        ]

        transitions: [
            Transition {
                to: "expanded"
                SmoothedAnimation {
                    target: overlayPanel
                    property: "y"
                    duration: LomiriAnimation.FastDuration
                    easing.type: Easing.Linear
                }
            },
            Transition {
                from: "expanded"
                to: "collapsed"
                SmoothedAnimation {
                    target: overlayPanel
                    property: "y"
                    duration: LomiriAnimation.SlowDuration
                }
            },
            Transition {
                from: "floating"
                to: "collapsed"
                SmoothedAnimation {
                    target: overlayPanel
                    property: "y"
                    duration: LomiriAnimation.FastDuration
                }
            }
        ]

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
                bottom: overlayRoot.miniBar.top
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
                bottom: overlayRoot.miniBar.top
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
                bottom: overlayRoot.miniBar.top
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
