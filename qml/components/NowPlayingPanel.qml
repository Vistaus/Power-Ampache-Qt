/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3

// Now Playing panel: full-grab, non-scrollable. The ENTIRE panel is
// the drag surface for the overlay sheet - the album cover is the
// big natural handle and dragging anywhere non-interactive moves the
// sheet. The interactive controls (progress bar, transport, shuffle/
// repeat) are declared AFTER the drag MouseArea so their taps always
// win. The cover fills the space above the bottom-anchored controls,
// square and aspect-fit (never stretched), hidden when the space is
// too flat to be worth showing. playback (the queue manager),
// audioEngine (the Audio element), formatDuration(seconds) and
// overlayRoot (the PlayerOverlay, for the drag machinery) are
// injected at the use site; anchors and visibility are set there too.
Item {
    id: nowPlayingPanelRoot

    property var playback
    property var audioEngine
    property var formatDuration
    property var overlayRoot

    // Compact mode: when the pane is too short to show the cover
    // (the same space class where the cover hides), the controls
    // column itself is taller than the pane and its top rows clip.
    // Compact tightens the spacing and drops the album row so
    // title/artist/bar/transport always fit at full font size.
    // Derived from the PANE height only - deriving it from the
    // column's own height would be a binding loop (compact changes
    // spacing, spacing changes the column height).
    readonly property bool compact: height < units.gu(40)

    // Whole-panel drag surface: FIRST child = lowest z, so every
    // interactive sibling declared below sits on top and keeps its
    // taps. Same direction-aware release machinery as the grabber
    // strip (2gu move sampling); pure taps are no-ops here (no
    // onClicked - tapping the cover does nothing, the pill keeps
    // tap-to-collapse).
    MouseArea {
        anchors.fill: parent
        property real previousY: -1
        property string dragDirection: 'None'
        drag {
            axis: Drag.YAxis
            target: overlayRoot ? overlayRoot.dragTarget : null
            minimumY: 0
            maximumY: overlayRoot ? overlayRoot.dragMaxY : 0
        }
        onPressed: {
            console.log('playerOverlay: panel press y=' + mouse.y)
            previousY = mouse.y
            dragDirection = 'None'
            if (overlayRoot) {
                overlayRoot.handlePressed()
            }
        }
        onPositionChanged: {
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
            console.log('playerOverlay: panel release direction=' + dragDirection)
            if (overlayRoot) {
                overlayRoot.handleReleased(dragDirection)
            }
            previousY = -1
            dragDirection = 'None'
        }
    }

    // Cover: fills the space above the controls. Square (album art
    // is square), centered, PreserveAspectFit inside the square so
    // the art is never stretched; placeholder icon when no art.
    Item {
        id: coverArea
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            bottom: controlsColumn.top
        }
        // Too flat to be worth showing (short 1-column windows; the
        // overlay itself is portrait-only) - the cover goes away and
        // the controls keep the whole panel.
        visible: height >= units.gu(24)

        Rectangle {
            id: coverSquare
            width: Math.min(coverArea.width, coverArea.height) - units.gu(4)
            height: width
            anchors.centerIn: parent
            color: theme.palette.normal.base

            Image {
                anchors.fill: parent
                source: playback.currentSong !== null ? playback.currentSong.imageUrl : ''
                visible: playback.currentSong !== null && playback.currentSong.imageUrl !== ''
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }

            Icon {
                anchors.centerIn: parent
                width: Math.max(units.gu(4), Math.min(units.gu(8), coverSquare.width / 3))
                height: width
                name: 'stock_music'
                visible: playback.currentSong === null || playback.currentSong.imageUrl === ''
            }
        }
    }

    // Bottom-anchored controls. Content unchanged from the old
    // scrollable layout (labels, progress bar, transport, shuffle/
    // repeat rows); only the container changed.
    Column {
        id: controlsColumn
        anchors {
            left: parent.left
            right: parent.right
            // Compact: center vertically so reclaimed space splits
            // evenly above and below instead of pooling at the top
            // (bottom-anchored overflow was the original clip bug).
            // No binding loop: compact derives from the pane height,
            // and the column's own height does not depend on its
            // anchors.
            bottom: compact ? undefined : parent.bottom
            verticalCenter: compact ? parent.verticalCenter : undefined
        }
        spacing: units.gu(2)

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: playback.currentSong !== null ? playback.currentSong.title : ''
            fontSize: 'large'
            font.bold: true
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: playback.currentSong !== null ? playback.currentSong.artistName : ''
            elide: Text.ElideRight
        }

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: playback.currentSong !== null ? playback.currentSong.albumName : ''
            fontSize: 'small'
            elide: Text.ElideRight
            // Column excludes invisible children from its layout,
            // so hiding the album row reclaims its height entirely.
            visible: !compact
        }

        Item {
            width: parent.width
            height: units.gu(5)

            ProgressBar {
                id: progressBar
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    leftMargin: units.gu(4)
                    rightMargin: units.gu(4)
                }
                minimumValue: 0
                // No bindings on audioEngine.duration/position:
                // same binding-loop cure as the time labels.
                // maximumValue is seeded/refreshed imperatively
                // via refreshProgressMaximum(); value is driven
                // by timeTicker below.
                maximumValue: 1
                value: 0
            }

            // Finger-friendly hit target over the display-only bar.
            MouseArea {
                anchors.left: progressBar.left
                anchors.verticalCenter: progressBar.verticalCenter
                width: progressBar.width
                height: units.gu(3)

                onClicked: {
                    if (nowPlayingPanelRoot.effectiveDurationMs() <= 0) {
                        return
                    }
                    var fraction = Math.max(0, Math.min(1, mouse.x / progressBar.width))
                    var targetMs = Math.round(fraction * progressBar.maximumValue)
                    // The bar is display-only; this jump sets it imperatively
                    // for instant feedback, then the 500ms timeTicker re-syncs
                    // after the stale-report drop.
                    progressBar.value = targetMs
                    playback.seekTo(targetMs)
                }
            }

            Label {
                id: positionLabel
                anchors {
                    left: parent.left
                    leftMargin: units.gu(4)
                    top: progressBar.bottom
                    topMargin: units.gu(0.5)
                }
                // No binding: updated imperatively by
                // timeTicker and on song change. Declarative
                // bindings on audioEngine.position/duration caused
                // the binding-loop warning.
                text: ''
                fontSize: 'small'
            }

            Label {
                id: durationLabel
                anchors {
                    right: parent.right
                    rightMargin: units.gu(4)
                    top: progressBar.bottom
                    topMargin: units.gu(0.5)
                }
                text: ''
                fontSize: 'small'
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: units.gu(4)
            height: units.gu(6)

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                width: units.gu(4)
                height: units.gu(4)
                name: 'media-skip-backward'

                MouseArea {
                    anchors.fill: parent
                    onClicked: playback.prev()
                }
            }

            Icon {
                width: units.gu(6)
                height: units.gu(6)
                name: playback.playing ? 'media-playback-pause' : 'media-playback-start'

                MouseArea {
                    anchors.fill: parent
                    onClicked: playback.togglePlayPause()
                }
            }

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                width: units.gu(4)
                height: units.gu(4)
                name: 'media-skip-forward'

                MouseArea {
                    anchors.fill: parent
                    onClicked: playback.next()
                }
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: units.gu(6)

            Icon {
                width: units.gu(3)
                height: units.gu(3)
                name: 'media-playlist-shuffle'
                opacity: playback.shuffle ? 1.0 : 0.3

                MouseArea {
                    anchors.fill: parent
                    onClicked: playback.toggleShuffle()
                }
            }

            Icon {
                width: units.gu(3)
                height: units.gu(3)
                name: playback.repeat === 'one' ? 'media-playlist-repeat-one' : 'media-playlist-repeat'
                opacity: playback.repeat === 'off' ? 0.3 : 1.0

                MouseArea {
                    anchors.fill: parent
                    onClicked: playback.cycleRepeat()
                }
            }
        }

        Item { width: 1; height: units.gu(1) }
    }

    // Total-time fallback (ms): the hub often cannot determine a
    // streamed source's duration and reports 0, so the song
    // payload's library duration ('time', seconds) stands in. A
    // real duration from the player wins once reported.
    function effectiveDurationMs() {
        if (audioEngine.duration > 0) {
            return audioEngine.duration
        }
        return playback.currentSong !== null ? playback.currentSong.time * 1000 : 0
    }

    // Imperative progress-bar maximum: the declarative binding on
    // audioEngine.duration caused the same binding-loop warning as
    // the time labels. Called at completion, on song change, and on
    // duration change. Guard 1 keeps maximumValue above minimumValue.
    function refreshProgressMaximum() {
        var dur = effectiveDurationMs()
        progressBar.maximumValue = dur > 0 ? dur : 1
    }

    // Imperative clock for the time labels. Must live inside this
    // component: positionLabel/durationLabel are component-scoped ids,
    // invisible at root scope. Runs only while playing.
    Timer {
        id: timeTicker
        interval: 500
        repeat: true
        running: playback.playing
        onTriggered: {
            // audioEngine.position/duration are ms; formatDuration
            // takes seconds. effectiveDurationMs covers the hub's
            // zero-duration streams with the library duration.
            positionLabel.text = nowPlayingPanelRoot.formatDuration(audioEngine.position / 1000)
            durationLabel.text = nowPlayingPanelRoot.formatDuration(nowPlayingPanelRoot.effectiveDurationMs() / 1000)
            progressBar.value = audioEngine.position
        }
    }

    Component.onCompleted: {
        // Diagnostic: measured pane height in grid units and the
        // resulting compact state. Remove after the threshold is
        // tuned.
        console.log('nowPlaying: panel height=' + height
            + ' gu=' + (height / units.gu(1)).toFixed(1)
            + ' compact=' + compact)
        // (Re)opened with a track already loaded but paused:
        // seed current values so the labels and the progress bar
        // are never blank.
        positionLabel.text = nowPlayingPanelRoot.formatDuration(audioEngine.position / 1000)
        durationLabel.text = nowPlayingPanelRoot.formatDuration(nowPlayingPanelRoot.effectiveDurationMs() / 1000)
        nowPlayingPanelRoot.refreshProgressMaximum()
        progressBar.value = audioEngine.position
    }

    Connections {
        target: playback
        onCurrentSongChanged: {
            // Reset the clock so a fresh/stopped track never shows
            // the previous track's times. Uses the song's own
            // duration (seconds) so a paused track shows 0:00 /
            // its length before the stream reports a duration.
            positionLabel.text = nowPlayingPanelRoot.formatDuration(0)
            durationLabel.text = nowPlayingPanelRoot.formatDuration(
                playback.currentSong !== null ? playback.currentSong.time : 0)
            // Reset the bar alongside the clock. If the hub still
            // reports the previous track's duration here, the
            // onDurationChanged handler below corrects the maximum
            // as soon as the new source's duration arrives.
            progressBar.value = 0
            nowPlayingPanelRoot.refreshProgressMaximum()
        }
    }

    // A real duration arriving from the player supersedes the
    // library fallback: refresh the bar maximum and the total-time
    // label imperatively (signal handler, not a binding, so no
    // binding loop on audioEngine.duration).
    Connections {
        target: audioEngine
        onDurationChanged: {
            nowPlayingPanelRoot.refreshProgressMaximum()
            durationLabel.text = nowPlayingPanelRoot.formatDuration(nowPlayingPanelRoot.effectiveDurationMs() / 1000)
        }
    }
}
