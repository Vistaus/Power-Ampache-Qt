/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3
import "../components"

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
                lyricsPanel.lyricsText = result.lyrics
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

    // Now Playing section.
    NowPlayingPanel {
        id: nowPlayingPanel
        playback: playerPage.playback
        audioEngine: playerPage.audioEngine
        formatDuration: playerPage.formatDuration
        anchors {
            top: playerPageHeader.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        visible: playerPageHeader.sections.selectedIndex === 0
    }

    // Queue section.
    QueuePanel {
        id: queuePanel
        playback: playerPage.playback
        anchors {
            top: playerPageHeader.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        visible: playerPageHeader.sections.selectedIndex === 1
    }

    // Lyrics section.
    LyricsPanel {
        id: lyricsPanel
        anchors {
            top: playerPageHeader.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        visible: playerPageHeader.sections.selectedIndex === 2
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
            if (playerPageHeader.sections.selectedIndex === 2) {
                playerPage.loadLyrics()
            }
        }
    }
}
