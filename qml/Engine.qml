/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import QtMultimedia 5.6

// The playback engine in ONE object. Architecture follows the
// ut-sonic-player pattern (store-shipped, device-tested):
// - ONE MediaPlayer with a native Playlist attached: the media-hub
//   owns the queue and advances tracks ITSELF. QML-side advancement
//   cannot work while the app is suspended (Lomiri freezes suspended
//   apps), but the hub is a system service and keeps running.
// - Warm-up priming: media-hub wedges PAUSED and silently drops
//   play() the first time it is asked to play after boot or a long
//   suspend. A SEPARATE MediaPlayer does not help - every instance
//   opens its own hub session - so the priming goes through THIS
//   player, on a bundled silence file, at startup and on every
//   re-activation, consuming the swallow before any user tap.
// - Supervisor watchdog: if play() is still swallowed, retry until
//   the position provably advances (capped; honest error at the
//   limit instead of silent stuck-ness).
// Consumers receive this object as their "playback" injection;
// pythonBridge (the Python element) is injected in Main.qml.
Item {
    id: engine

    property var pythonBridge
    property alias audioElement: audio

    // Song metadata PARALLEL to hubPlaylist's URLs (same order, same
    // indices): the playlist holds only stream URLs, the UI reads
    // titles/artists from here. queue holds song dicts as returned by
    // bridge.getAlbumSongs (id, title, trackNumber, artistName,
    // albumId, albumName, time, imageUrl). Shuffle shuffles this
    // array eagerly at playFrom() time; the hub never reshuffles.
    // repeat is 'off' | 'all' | 'one'; the playbackMode binding maps
    // it to hub-native behavior.
    property var queue: []
    property bool shuffle: false
    property string repeat: 'off'
    // JS mirror of hubPlaylist.currentIndex. The hub updates
    // currentIndex asynchronously, which races UI bindings, so all
    // reads go through this sync'd copy.
    property int playerIndex: -1
    readonly property var currentSong: (playerIndex >= 0 && playerIndex < queue.length) ? queue[playerIndex] : null
    readonly property bool playing: audio.playbackState === MediaPlayer.PlayingState

    // True while the warm-up silence is running through the hub.
    property bool warmingUp: false

    // Suppresses onCurrentIndexChanged during our own playlist
    // surgery (clear/addItems).
    property bool rebuilding: false

    // Core contract: tap in the middle of any list plays the whole
    // list from there (album now; playlists later). The whole queue
    // is handed to the hub as stream URLs in one bridge call.
    function playFrom(list, startIndex) {
        console.log('engine: playFrom list=' + list.length + ' start=' + startIndex + ' shuffle=' + shuffle)
        warmingUp = false   // a real request overrides an in-flight warm-up
        // Eager shuffle (sonic pattern): the chosen song first, the
        // rest shuffled behind it. Applies at queue start only;
        // toggling shuffle mid-queue takes effect on the next
        // playFrom().
        var eff = list.slice()
        var start = startIndex
        if (shuffle && eff.length > 1) {
            var chosen = eff.splice(startIndex, 1)[0]
            for (var i = eff.length - 1; i > 0; i--) {
                var j = Math.floor(Math.random() * (i + 1))
                var tmp = eff[i]; eff[i] = eff[j]; eff[j] = tmp
            }
            eff.unshift(chosen)
            start = 0
        }
        // DEFAULT stats (stats argument omitted on purpose): real
        // user plays feed the listen history. Never log the URLs -
        // they embed the live session token.
        var ids = []
        for (var k = 0; k < eff.length; k++) {
            ids.push(eff[k].id)
        }
        pythonBridge.call('bridge.getStreamUrls', [ids], function(result) {
            console.log('engine: stream urls ok=' + (result ? result.ok : false) + ' count=' + (result && result.urls ? result.urls.length : 0))
            if (!result || !result.ok) {
                // Leave the player stopped; error surfacing is future
                // work.
                return
            }
            queue = eff
            playerIndex = start
            rebuilding = true
            console.log('engine: hubPlaylist.clear()')
            hubPlaylist.clear()
            console.log('engine: hubPlaylist.addItems count=' + result.urls.length)
            hubPlaylist.addItems(result.urls)
            rebuilding = false
            console.log('engine: hubPlaylist.currentIndex ' + hubPlaylist.currentIndex + ' -> ' + start)
            hubPlaylist.currentIndex = start
            playWithWatchdog()
        })
    }

    function togglePlayPause() {
        if (audio.playbackState === MediaPlayer.PlayingState) {
            playWatchdog.stop()
            audio.pause()
        } else if (currentSong !== null) {
            playWithWatchdog()
        }
    }

    function toggleShuffle() {
        shuffle = !shuffle
    }

    function cycleRepeat() {
        repeat = repeat === 'off' ? 'all' : (repeat === 'all' ? 'one' : 'off')
    }

    // Manual next/prev. "next does not enforce play" (sonic): the
    // playlist move alone does not start a stopped player, so play()
    // explicitly after moving. Prev at the first track does nothing
    // (hub Sequential stops at index 0).
    function next() {
        if (playerIndex < 0) {
            return
        }
        if (playerIndex + 1 < queue.length) {
            hubPlaylist.next()
            if (audio.playbackState !== MediaPlayer.PlayingState) {
                playWithWatchdog()
            }
        } else if (repeat === 'all') {
            console.log('engine: hubPlaylist.currentIndex ' + hubPlaylist.currentIndex + ' -> 0')
            hubPlaylist.currentIndex = 0
            if (audio.playbackState !== MediaPlayer.PlayingState) {
                playWithWatchdog()
            }
        }
    }

    function prev() {
        if (playerIndex <= 0) {
            return
        }
        hubPlaylist.previous()
        if (audio.playbackState !== MediaPlayer.PlayingState) {
            playWithWatchdog()
        }
    }

    // --- Supervisor watchdog (sonic playWatchdog, album-scale) -----
    // After every play(), check every 1.5s that the position actually
    // advanced. Plain play() on retries 1-2; pause() + 100ms + play()
    // from retry 3 on (streams need the pause-reset; the disruption
    // is harmless because playback has not started). Success = the
    // position moved. Cap 20 = give up honestly. Replaces the old
    // one-shot kick, which had no answer if its own play() was
    // swallowed.
    property int watchdogRetries: 0
    property int watchdogLastPos: 0
    property bool watchdogEverPlayed: false

    function playWithWatchdog() {
        console.log('engine: playWithWatchdog armed state=' + audio.playbackState)
        watchdogRetries = 0
        watchdogLastPos = 0
        watchdogEverPlayed = false
        playWatchdog.restart()
        audio.play()
    }

    Timer {
        id: playWatchdog
        interval: 1500
        repeat: true
        onTriggered: {
            console.log('engine: watchdog tick retries=' + engine.watchdogRetries + ' pos=' + audio.position + ' state=' + audio.playbackState)
            // The everPlayed latch (set by onPositionChanged) counts
            // as success alongside a sampled position advance.
            if (engine.watchdogEverPlayed || audio.position > engine.watchdogLastPos) {
                engine.watchdogEverPlayed = true
                console.log('engine: watchdog success reason=' + (engine.watchdogEverPlayed ? 'latch' : 'position') + ' warmingUp=' + engine.warmingUp)
                stop()
                if (engine.warmingUp) engine.finishWarmUp()
                return
            }
            engine.watchdogRetries++
            if (engine.watchdogRetries >= 20) {
                stop()
                if (engine.warmingUp) {
                    engine.finishWarmUp()
                    return
                }
                // Honest failure instead of silent stuck-ness. The
                // hub left the queue untouched; the mini-bar hides.
                console.log('engine: watchdog retry cap reached, giving up')
                console.log('playback failed: watchdog retry cap reached')
                engine.playerIndex = -1
                return
            }
            engine.watchdogLastPos = audio.position
            if (engine.watchdogRetries >= 3) {
                console.log('engine: watchdog action pause+100ms+play retry=' + engine.watchdogRetries)
                audio.pause()
                watchdogPlayTimer.restart()
            } else {
                console.log('engine: watchdog action play retry=' + engine.watchdogRetries)
                audio.play()
            }
        }
    }

    Timer {
        id: watchdogPlayTimer
        interval: 100
        onTriggered: audio.play()
    }

    // --- Warm-up priming (sonic _warmUpMediaHub) -------------------
    // Drive THIS player through the bundled silence file so the hub
    // session is primed before the user taps anything. Skipped once a
    // real queue has played (playerIndex >= 0) and while anything is
    // active - mid-queue reactivation relies on the hub still owning
    // the tracklist, which is exactly what the device experiment
    // tests.
    function warmUpMediaHub() {
        if (warmingUp || playerIndex >= 0
                || audio.playbackState !== MediaPlayer.StoppedState) {
            return
        }
        warmingUp = true
        rebuilding = true
        console.log('engine: hubPlaylist.clear()')
        hubPlaylist.clear()
        console.log('engine: hubPlaylist.addItem count=1 (warm-up silence)')
        hubPlaylist.addItem(Qt.resolvedUrl('../assets/warmup-silence.wav'))
        rebuilding = false
        console.log('engine: hubPlaylist.currentIndex ' + hubPlaylist.currentIndex + ' -> 0')
        hubPlaylist.currentIndex = 0
        playWithWatchdog()
    }

    function finishWarmUp() {
        warmingUp = false
        playWatchdog.stop()
        rebuilding = true
        console.log('engine: hubPlaylist.clear()')
        hubPlaylist.clear()
        rebuilding = false
    }

    Component.onCompleted: warmUpMediaHub()

    // Re-prime after returning from a background suspension, where
    // the hub service may have been reaped - same cold-start risk as
    // boot.
    Connections {
        target: Qt.application
        onActiveChanged: {
            if (Qt.application.active) engine.warmUpMediaHub()
        }
    }

    MediaPlayer {
        id: audio
        autoPlay: false
        audioRole: MediaPlayer.MusicRole

        onPlaybackStateChanged: console.log('engine: playbackState=' + playbackState)
        onStatusChanged: console.log('engine: status=' + status)

        // everPlayed latch: any forward progress proves the hub
        // really played. The watchdog's 1.5s sampling can miss a
        // short file (the warm-up silence) that already played
        // through, so position itself records the proof. Lets the
        // warm-up self-terminate once played instead of being
        // replayed by watchdog retries. playWithWatchdog() clears
        // the latch per attempt, so a stale value never fakes
        // success for the next track.
        onPositionChanged: {
            if (position > 0) {
                if (!engine.watchdogEverPlayed) {
                    console.log('engine: first position advance pos=' + position)
                }
                engine.watchdogEverPlayed = true
            }
        }

        playlist: Playlist {
            id: hubPlaylist

            // Hub-native repeat: 'one' loops the current item, 'all'
            // wraps the queue, 'off' stops at the end. Note: the hub
            // replays the SAME stream URL for 'one'; if it re-fetches
            // the URL the server records a play per loop (the old
            // engine seeked to 0 instead). Known edge, reviewed at PR.
            playbackMode: engine.repeat === 'one' ? Playlist.CurrentItemInLoop
                       : engine.repeat === 'all' ? Playlist.Loop
                       : Playlist.Sequential

            onCurrentIndexChanged: {
                if (currentIndex < 0 || engine.rebuilding) {
                    return
                }
                engine.playerIndex = currentIndex
            }
        }
    }
}
