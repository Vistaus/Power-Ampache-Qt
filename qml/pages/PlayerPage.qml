/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3
import QtMultimedia 5.0

// Full player screen with three header sections: Now Playing, Queue,
// Lyrics. playback (the queue manager), pythonBridge (the Python
// element), audioEngine (the Audio element) and formatDuration(seconds)
// are injected at the use site.
Page {
    id: playerPage
    objectName: 'playerPage'

    property var playback
    property var pythonBridge
    property var audioEngine
    property var formatDuration

    header: PageHeader {
        id: playerPageHeader
        title: i18n.tr('Now Playing')

        // Segmented control drives the three sections below.
        // sections is read-only: populate the model at completion,
        // never assign sections directly.
        Component.onCompleted: {
            sections.model = [i18n.tr('Now Playing'), i18n.tr('Queue')]
        }
    }

    // Lyrics load lazily: only when the Lyrics section (index 2)
    // opens, and again if the song changes while it is showing.
    // The Lyrics section exists in the model ONLY when the current
    // song has lyrics.
    function loadLyrics() {
        if (playback.currentSong === null) {
            setLyricsSection(false)
            return
        }
        pythonBridge.call('bridge.getLyrics', [playback.currentSong.id], function(result) {
            if (result && result.ok && result.lyrics !== '') {
                lyricsLabel.text = result.lyrics
                setLyricsSection(true)
            } else {
                setLyricsSection(false)
            }
        })
    }

    // Add or remove the Lyrics section. Model changes reset
    // selectedIndex, so restore it afterwards and never leave it
    // pointing past the end of the model.
    function setLyricsSection(present) {
        var model = header.sections.model
        var hasLyrics = model.length > 2
        if (present === hasLyrics) {
            return
        }
        var selected = header.sections.selectedIndex
        if (present) {
            header.sections.model = [i18n.tr('Now Playing'), i18n.tr('Queue'), i18n.tr('Lyrics')]
        } else {
            header.sections.model = [i18n.tr('Now Playing'), i18n.tr('Queue')]
            if (selected > 1) {
                selected = 0
            }
        }
        header.sections.selectedIndex = selected
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

    // Now Playing section.
    Flickable {
        id: nowPlayingFlickable
        anchors {
            top: playerPageHeader.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        visible: playerPageHeader.sections.selectedIndex === 0
        contentWidth: width
        contentHeight: nowPlayingColumn.implicitHeight
        clip: true

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
    }

    // Queue section.
    ListView {
        id: queueListView
        anchors {
            top: playerPageHeader.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        visible: playerPageHeader.sections.selectedIndex === 1
        clip: true
        model: playback.queue

        delegate: Item {
            width: queueListView.width
            height: units.gu(6)

            Rectangle {
                anchors.fill: parent
                color: index === playback.playerIndex
                       ? theme.palette.normal.base : 'transparent'
            }

            Column {
                anchors {
                    left: parent.left
                    leftMargin: units.gu(2)
                    right: parent.right
                    rightMargin: units.gu(2)
                    verticalCenter: parent.verticalCenter
                }

                Label {
                    width: parent.width
                    text: modelData.title
                    font.bold: index === playback.playerIndex
                    elide: Text.ElideRight
                }

                Label {
                    width: parent.width
                    text: modelData.artistName
                    fontSize: 'small'
                    elide: Text.ElideRight
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: playback.playFrom(playback.queue, index)
            }
        }
    }

    // Lyrics section.
    Flickable {
        id: lyricsFlickable
        anchors {
            top: playerPageHeader.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        visible: playerPageHeader.sections.selectedIndex === 2
        contentWidth: width
        contentHeight: lyricsLabel.height + units.gu(4)
        clip: true

        Label {
            id: lyricsLabel
            x: units.gu(2)
            y: units.gu(2)
            width: lyricsFlickable.width - units.gu(4)
            wrapMode: Text.Wrap
        }
    }

    // Imperative clock for the time labels. Must live inside this
    // component: positionLabel/durationLabel are page-scoped ids,
    // invisible at root scope. Runs only while playing.
    Timer {
        id: timeTicker
        interval: 500
        repeat: true
        running: audioEngine.playbackState === MediaPlayer.PlayingState
        onTriggered: {
            // audioEngine.position/duration are ms; formatDuration
            // takes seconds. effectiveDurationMs covers the hub's
            // zero-duration streams with the library duration.
            positionLabel.text = playerPage.formatDuration(audioEngine.position / 1000)
            durationLabel.text = playerPage.formatDuration(playerPage.effectiveDurationMs() / 1000)
            progressBar.value = audioEngine.position
        }
    }

    Component.onCompleted: {
        // Page (re)opened with a track already loaded but paused:
        // seed current values so the labels and the progress bar
        // are never blank.
        positionLabel.text = playerPage.formatDuration(audioEngine.position / 1000)
        durationLabel.text = playerPage.formatDuration(playerPage.effectiveDurationMs() / 1000)
        playerPage.refreshProgressMaximum()
        progressBar.value = audioEngine.position
    }

    Connections {
        target: playerPageHeader.sections
        onSelectedIndexChanged: {
            if (playerPageHeader.sections.selectedIndex === 2) {
                playerPage.loadLyrics()
            }
        }
    }

    Connections {
        target: playback
        onCurrentSongChanged: {
            // Reset the clock so a fresh/stopped track never shows
            // the previous track's times. Uses the song's own
            // duration (seconds) so a paused track shows 0:00 /
            // its length before the stream reports a duration.
            positionLabel.text = playerPage.formatDuration(0)
            durationLabel.text = playerPage.formatDuration(
                playback.currentSong !== null ? playback.currentSong.time : 0)
            // Reset the bar alongside the clock. If the hub still
            // reports the previous track's duration here, the
            // onDurationChanged handler below corrects the maximum
            // as soon as the new source's duration arrives.
            progressBar.value = 0
            playerPage.refreshProgressMaximum()
            if (playerPageHeader.sections.selectedIndex === 2) {
                playerPage.loadLyrics()
            }
        }
    }

    // A real duration arriving from the player supersedes the
    // library fallback: refresh the bar maximum and the total-time
    // label imperatively (signal handler, not a binding, so no
    // binding loop on audioEngine.duration).
    Connections {
        target: audioEngine
        onDurationChanged: {
            playerPage.refreshProgressMaximum()
            durationLabel.text = playerPage.formatDuration(playerPage.effectiveDurationMs() / 1000)
        }
    }
}
