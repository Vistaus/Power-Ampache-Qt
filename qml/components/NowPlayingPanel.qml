/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3

// Now Playing panel: artwork, title/artist/album labels, progress bar
// with time labels, transport and shuffle/repeat rows, plus the
// imperative clock machinery that drives them. playback (the queue
// manager), audioEngine (the Audio element) and formatDuration(seconds)
// are injected at the use site; anchors and visibility are set there too.
Flickable {
    id: nowPlayingFlickable

    property var playback
    property var audioEngine
    property var formatDuration

    contentWidth: width
    contentHeight: nowPlayingColumn.implicitHeight
    clip: true

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

    Column {
        id: nowPlayingColumn
        width: parent.width
        spacing: units.gu(2)

        Item { width: 1; height: units.gu(1) }

        Rectangle {
            width: units.gu(24)
            height: width
            anchors.horizontalCenter: parent.horizontalCenter
            color: theme.palette.normal.base

            Image {
                anchors.fill: parent
                source: playback.currentSong !== null ? playback.currentSong.imageUrl : ''
                visible: playback.currentSong !== null && playback.currentSong.imageUrl !== ''
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }

            Icon {
                anchors.centerIn: parent
                width: units.gu(8)
                height: units.gu(8)
                name: 'stock_music'
                visible: playback.currentSong === null || playback.currentSong.imageUrl === ''
            }
        }

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: playback.currentSong !== null ? playback.currentSong.title : ''
            fontSize: 'large'
            font.bold: true
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
            positionLabel.text = nowPlayingFlickable.formatDuration(audioEngine.position / 1000)
            durationLabel.text = nowPlayingFlickable.formatDuration(nowPlayingFlickable.effectiveDurationMs() / 1000)
            progressBar.value = audioEngine.position
        }
    }

    Component.onCompleted: {
        // Page (re)opened with a track already loaded but paused:
        // seed current values so the labels and the progress bar
        // are never blank.
        positionLabel.text = nowPlayingFlickable.formatDuration(audioEngine.position / 1000)
        durationLabel.text = nowPlayingFlickable.formatDuration(nowPlayingFlickable.effectiveDurationMs() / 1000)
        nowPlayingFlickable.refreshProgressMaximum()
        progressBar.value = audioEngine.position
    }

    Connections {
        target: playback
        onCurrentSongChanged: {
            // Reset the clock so a fresh/stopped track never shows
            // the previous track's times. Uses the song's own
            // duration (seconds) so a paused track shows 0:00 /
            // its length before the stream reports a duration.
            positionLabel.text = nowPlayingFlickable.formatDuration(0)
            durationLabel.text = nowPlayingFlickable.formatDuration(
                playback.currentSong !== null ? playback.currentSong.time : 0)
            // Reset the bar alongside the clock. If the hub still
            // reports the previous track's duration here, the
            // onDurationChanged handler below corrects the maximum
            // as soon as the new source's duration arrives.
            progressBar.value = 0
            nowPlayingFlickable.refreshProgressMaximum()
        }
    }

    // A real duration arriving from the player supersedes the
    // library fallback: refresh the bar maximum and the total-time
    // label imperatively (signal handler, not a binding, so no
    // binding loop on audioEngine.duration).
    Connections {
        target: audioEngine
        onDurationChanged: {
            nowPlayingFlickable.refreshProgressMaximum()
            durationLabel.text = nowPlayingFlickable.formatDuration(nowPlayingFlickable.effectiveDurationMs() / 1000)
        }
    }
}
