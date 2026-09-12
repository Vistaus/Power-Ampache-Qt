/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import QtMultimedia 5.0

// The playback engine in ONE object: the Audio element, the
// device-only play()-swallow watchdog (playWatchdog + playKick), and
// the queue manager (play order, shuffle, repeat). Consumers receive
// this object as their "playback" injection; pythonBridge (the Python
// element) is injected at the use site in Main.qml.
Item {
    id: engine

    property var pythonBridge
    property alias audioElement: audio

    Audio {
        id: audio
        // No auto-play: source is set only by the queue logic below.

        onStopped: {
            // Natural end goes through engine.onNaturalEnd() (repeat
            // 'one' replays there, and ONLY there). Setting a new source
            // also stops playback, so gate strictly on EndOfMedia.
            if (status === MediaPlayer.EndOfMedia) {
                engine.onNaturalEnd()
            }
        }
    }

    // Watchdog for the device-only media-hub first-play swallow: the hub
    // session drops play() until a pause() has primed its state machine.
    // 2s after every play() we check whether playback actually advanced.
    Timer {
        id: playWatchdog
        interval: 2000
        onTriggered: engine.playWatchdogCheck()
    }

    // The kick itself: pause() then play(), the sequence proven to work
    // manually. 1000ms gap - replicates the twice-proven manual gap from
    // the device logs; shorter may race the hub's pause state transition.
    Timer {
        id: playKick
        interval: 1000
        onTriggered: audio.play()
    }

    // The ONE owner of play order. queue holds song dicts as returned
    // by bridge.getAlbumSongs (id, title, trackNumber, artistName,
    // albumId, albumName, time, imageUrl).
    // comes NEXT without mutating the queue; repeat is 'off' | 'all'
    // | 'one'. Queue editing is future work.
    property var queue: []
    property int currentIndex: -1
    property bool shuffle: false
    property string repeat: 'off'   // 'off' | 'all' | 'one'
    // Indices already played in shuffle mode: no repeats until the
    // queue is exhausted. Reset by playFrom() and toggleShuffle().
    property var playedIndices: []
    // Set by playCurrentSong(); the playWatchdog timer consumes it
    // to detect a swallowed play (device-only).
    property bool playbackKickPending: false
    readonly property var currentSong: (currentIndex >= 0 && currentIndex < queue.length) ? queue[currentIndex] : null
    readonly property bool playing: audio.playbackState === MediaPlayer.PlayingState

    // Core contract: tap in the middle of any list plays the whole
    // list from there (album now; playlists later).
    function playFrom(list, startIndex) {
        queue = list
        currentIndex = startIndex
        playedIndices = [startIndex]
        playCurrentSong()
    }

    function togglePlayPause() {
        if (audio.playbackState === MediaPlayer.PlayingState) {
            audio.pause()
        } else if (currentSong !== null) {
            audio.play()
        }
    }

    function toggleShuffle() {
        shuffle = !shuffle
        // Re-seed the played-set with the current song so it is never
        // re-picked (randomUnplayedIndex also excludes it directly).
        playedIndices = currentIndex >= 0 ? [currentIndex] : []
    }

    function cycleRepeat() {
        repeat = repeat === 'off' ? 'all' : (repeat === 'all' ? 'one' : 'off')
    }

    // A random queue index not yet played in shuffle mode; -1 when the
    // queue is exhausted. Never returns the current index.
    function randomUnplayedIndex() {
        var unplayed = []
        for (var i = 0; i < queue.length; i++) {
            if (i !== currentIndex && playedIndices.indexOf(i) === -1) {
                unplayed.push(i)
            }
        }
        if (unplayed.length === 0) {
            return -1
        }
        return unplayed[Math.floor(Math.random() * unplayed.length)]
    }

    // Natural end of a song (Audio EndOfMedia). Repeat 'one' replays
    // here and ONLY here - manual prev/next taps always move.
    function onNaturalEnd() {
        if (repeat === 'one' && currentSong !== null) {
            // Seek-restart, not playCurrentSong(): re-fetching the URL
            // with default stats would record a second play.
            audio.seek(0)
            audio.play()
            return
        }
        next()
    }

    // Shared end-of-queue behavior for next(): repeat 'all' wraps to
    // the top, everything else keeps the stop-and-clear behavior.
    function handleQueueEnd() {
        if (repeat === 'all' && queue.length > 0) {
            currentIndex = 0
            playedIndices = [0]
            playCurrentSong()
        } else {
            audio.stop()
            currentIndex = -1
        }
    }

    function next() {
        if (currentIndex < 0) {
            return
        }
        if (shuffle) {
            var shuffledIndex = randomUnplayedIndex()
            if (shuffledIndex >= 0) {
                currentIndex = shuffledIndex
                playedIndices.push(shuffledIndex)
                playCurrentSong()
            } else {
                // Every song played: shuffle's end-of-queue.
                handleQueueEnd()
            }
            return
        }
        if (currentIndex + 1 < queue.length) {
            currentIndex = currentIndex + 1
            playCurrentSong()
        } else {
            handleQueueEnd()
        }
    }

    function prev() {
        if (currentIndex < 0) {
            return
        }
        if (shuffle) {
            var shuffledIndex = randomUnplayedIndex()
            if (shuffledIndex >= 0) {
                currentIndex = shuffledIndex
                playedIndices.push(shuffledIndex)
                playCurrentSong()
            } else if (currentSong !== null) {
                // Nothing unplayed: restart the current song, mirroring
                // the first-track case below.
                audio.seek(0)
            }
            return
        }
        if (currentIndex > 0) {
            currentIndex = currentIndex - 1
            playCurrentSong()
        } else if (currentSong !== null) {
            // First track restarts via seek - re-fetching the URL with
            // default stats would record a second play.
            audio.seek(0)
        }
    }

    function playCurrentSong() {
        var song = currentSong
        if (song === null) {
            return
        }
        // DEFAULT stats (stats argument omitted on purpose): real user
        // plays feed the listen history. any test or prefetch must pass stats=0.
        // Never log result.url - it embeds the session token.
        pythonBridge.call('bridge.getStreamUrl', [song.id], function(result) {
            if (result && result.ok) {
                audio.source = result.url
                audio.play()
                playbackKickPending = true
                playWatchdog.restart()
            }
            // On failure leave the player stopped; session 3 owns error
            // surfacing.
        })
    }

    // Watchdog check, 2s after every play(). Device-proven signatures:
    // - swallowed play: PausedState + position frozen at 0 -> the
    //   pause+play kick, which the hub accepts;
    // - working play: PlayingState + advancing position -> no kick
    //   (desktop and normal starts);
    // - slow buffer: Buffering/Stalled status -> re-arm the watchdog
    //   and keep the flag, extending the deadline instead of silently
    //   disabling the kick.
    // One kick attempt only, never a kick loop: playbackKickPending is
    // cleared before any kick.
    function playWatchdogCheck() {
        if (!playbackKickPending) {
            return
        }
        // The swallow check is device-proven - semantics unchanged.
        // Flag cleared before the kick, as before.
        if (audio.playbackState === MediaPlayer.PausedState && audio.position < 250) {
            playbackKickPending = false
            audio.pause()
            playKick.restart()
            return
        }
        // Not swallowed, still buffering: keep the flag and re-arm so
        // a slow network extends the deadline rather than consuming
        // the one kick attempt.
        if (audio.status === MediaPlayer.Buffering || audio.status === MediaPlayer.Stalled) {
            playWatchdog.restart()
            return
        }
        // Working play (or any other state): consume the flag, no kick.
        playbackKickPending = false
    }
}
