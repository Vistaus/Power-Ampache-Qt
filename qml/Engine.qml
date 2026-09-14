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
// - Stop-then-commit, target-first: the hub playlist is rebuilt
//   only on a confirmed-stopped session (2s timeout fallback), and
//   rotated so the tapped track is item 0. A currentIndex jump on a
//   live session makes the hub open item 0, abandon the open, and
//   wedge - it then accepts play() but never plays (device logs).
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
    // JS mirror of the hub position, derived through queueStart
    // (below). The hub updates currentIndex asynchronously, which
    // races UI bindings, so all reads go through this sync'd copy.
    property int playerIndex: -1
    // Rotation offset between queue and the hub playlist: hub item 0
    // holds queue[queueStart], so the UI position is always derived
    // as playerIndex = (queueStart + hubIndex) % queue.length.
    // queue keeps original album order; the hub playlist is the
    // rotated view of it.
    property int queueStart: 0
    readonly property var currentSong: (playerIndex >= 0 && playerIndex < queue.length) ? queue[playerIndex] : null
    // Imperative "is playing" truth. NEVER bind this to
    // audio.playbackState: a late StoppedState echo from the old
    // session's teardown stomps playbackState while the new session
    // actually plays (device log). Set true by onPlaybackStateChanged
    // and togglePlayPause; playingTruthSampler alone owns false.
    property bool playing: false
    // Last position (ms) sampled by playingTruthSampler.
    property int lastSampledPos: 0

    // True while the warm-up silence is running through the hub.
    property bool warmingUp: false

    // Suppresses onCurrentIndexChanged during our own playlist
    // surgery (clear/addItems).
    property bool rebuilding: false
    // --- Stop-then-commit state ------------------------------------
    // The next queue awaiting a safe commit point:
    // {'songs': effective queue, 'start': tapped index, 'urls':
    // rotated stream URLs}. Written by playFrom's bridge callback,
    // consumed by commitQueue() exactly once.
    property var pendingCommit: null
    // State gate pairing one stop() with one StoppedState
    // confirmation. StoppedState echoes from our own stop/clear
    // during commit find this already false and are ignored - they
    // can neither re-trigger nor advance anything.
    property bool awaitingStop: false
    // Timestamp (Date.now()) of the last commitQueue() rebuild.
    // Anchors the 400ms window in which a StoppedState is known to
    // be the old session's late teardown echo (sonic pattern).
    property real lastCommitMs: 0

    // --- EndOfMedia fallback state ---------------------------------
    // Hub index captured at EndOfMedia; -2 = disarmed (hub indices
    // are >= -1). Consumed by eomFallbackTimer.
    property int eomArmedIndex: -2

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
            // Target-first rotation: the tapped track's URL becomes
            // hub item 0, the rest of the queue follows in order,
            // and the tracks before the tapped one append at the
            // end. The hub therefore never sees an index jump - item
            // 0 is always what it opens first (a mid-flight jump is
            // exactly what wedged it in the device logs). queue
            // itself keeps original album order for the UI.
            var rotated
            if (repeat === 'off') {
                // Tail only: the hub playlist ends at the queue end,
                // so the hub's native Sequential stop coincides with
                // it. Wrapping the pre-tapped songs to the end would
                // make one Sequential pass play every queue item once
                // (a full cycle).
                rotated = result.urls.slice(start)
            } else {
                rotated = result.urls.slice(start).concat(result.urls.slice(0, start))
            }
            // A repeat mode changed mid-queue takes full effect from
            // the next playFrom: the playbackMode binding is live,
            // but the playlist shape (tail vs full rotation) is fixed
            // at commit. queue/playerIndex math is unchanged - with
            // the tail, (queueStart + hubIndex) % queue.length never
            // wraps.
            pendingCommit = {'songs': eff, 'start': start, 'urls': rotated}
            requestCommit()
        })
    }

    // Stop-then-commit: rebuilding the hub playlist while anything
    // is loaded is forbidden - a clear+addItems on a live session
    // wedges the hub (it accepts play() but never plays). Already
    // stopped = commit immediately; otherwise stop() first and defer
    // the rebuild until StoppedState confirms, with a 2s timeout
    // fallback so a tap is never dropped.
    function requestCommit() {
        if (audio.playbackState === MediaPlayer.StoppedState) {
            commitQueue()
            return
        }
        if (awaitingStop) {
            // A stop is already in flight; its confirmation will
            // commit the latest pendingCommit.
            return
        }
        console.log('engine: commit stop requested state=' + audio.playbackState)
        // Silence the watchdog while the old session winds down -
        // its retries would play() the very session being stopped.
        // commitQueue() re-arms it for the new queue.
        playWatchdog.stop()
        watchdogPlayTimer.stop()
        awaitingStop = true
        stopConfirmTimer.start()
        audio.stop()
    }

    // The ONLY place the hub playlist is mutated, entered solely
    // from a confirmed (or timed-out) stopped state. currentIndex is
    // assigned here and nowhere else, and only while the fresh
    // playlist still sits at -1: after addItems the hub opens item 0
    // on its own, and a second explicit index assignment on a live
    // session is what wedged it (open item 0, abandon, re-open).
    // Rotation makes the tapped track item 0, so no jump is ever
    // needed.
    function commitQueue() {
        var pending = pendingCommit
        pendingCommit = null
        if (!pending) {
            return
        }
        engine.lastCommitMs = Date.now()
        queue = pending.songs
        queueStart = pending.start
        lastSampledPos = 0
        console.log('engine: commit rebuilding hub playlist count=' + pending.urls.length)
        rebuilding = true
        console.log('engine: hubPlaylist.clear()')
        hubPlaylist.clear()
        console.log('engine: hubPlaylist.addItems count=' + pending.urls.length)
        hubPlaylist.addItems(pending.urls)
        rebuilding = false
        if (hubPlaylist.currentIndex < 0) {
            console.log('engine: hubPlaylist.currentIndex ' + hubPlaylist.currentIndex + ' -> 0')
            hubPlaylist.currentIndex = 0
        }
        // Synchronous mirror of the hub position (hubIndex 0 after a
        // fresh build): the hub's own currentIndex update is async
        // and races UI bindings.
        playerIndex = queue.length > 0 ? queueStart % queue.length : -1
        playWithWatchdog()
    }

    function togglePlayPause() {
        if (engine.playing) {
            playWatchdog.stop()
            engine.playing = false
            audio.pause()
        } else if (currentSong !== null) {
            // Optimistic: the truth sampler corrects within 1s if the
            // hub swallows the play.
            engine.playing = true
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
    // explicitly after moving.
    function next() {
        if (playerIndex < 0) {
            return
        }
        // Hub-advance only: repeat 'all' wraps natively
        // (Playlist.Loop), so the old explicit wrap-to-0 index
        // assignment is removed - no index assignments outside
        // commit. At the last hub item with repeat off, Sequential
        // clamps and the advance is a no-op.
        hubPlaylist.next()
        if (audio.playbackState !== MediaPlayer.PlayingState) {
            playWithWatchdog()
        }
    }

    function prev() {
        // Behavior change under rotation: the guard is the HUB's
        // index, not the queue position. Hub item 0 is the tapped
        // track (the rotated start); the tracks before it wrapped to
        // the END of the hub playlist, so prev() never walks back
        // into them - they are reached only by playing the queue
        // through.
        if (playerIndex < 0 || hubPlaylist.currentIndex <= 0) {
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
            // Proof of audio only: the everPlayed latch (set by
            // onPositionChanged, itself gated on position > 0) or a
            // sampled advance to a POSITIVE position. A wedged hub
            // reports garbage negative positions; a recovery from
            // garbage back to 0 must never count as "advanced".
            if (engine.watchdogEverPlayed
                    || (audio.position > 0 && audio.position > engine.watchdogLastPos)) {
                engine.watchdogEverPlayed = true
                console.log('engine: watchdog success reason=' + (engine.watchdogEverPlayed ? 'latch' : 'position') + ' warmingUp=' + engine.warmingUp)
                stop()
                if (engine.warmingUp) engine.finishWarmUp()
                return
            }
            engine.watchdogRetries++
            if (engine.watchdogRetries >= 20) {
                stop()
                // Leave the hub in a clean stopped state - a wedged
                // session must not linger half-open.
                audio.stop()
                engine.playing = false
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
            // Baseline discipline: only a positive sample becomes the
            // new baseline. A negative or 0 sample is skipped
            // entirely - adopting a garbage negative baseline would
            // let a later 0 look like an advance.
            if (audio.position > 0) {
                engine.watchdogLastPos = audio.position
            } else {
                console.log('engine: watchdog skipped baseline update pos=' + audio.position)
            }
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

    // 2s fallback for the stop-then-commit: if no StoppedState
    // confirmation arrives, commit anyway rather than drop the tap.
    Timer {
        id: stopConfirmTimer
        interval: 2000
        onTriggered: {
            if (!engine.awaitingStop) {
                return
            }
            engine.awaitingStop = false
            console.log('engine: commit stop confirmation timeout, proceeding anyway')
            engine.commitQueue()
        }
    }

    // --- EndOfMedia fallback ---------------------------------------
    // With playbackState poisoned by the late teardown echo, the
    // backend may not advance the playlist at EndOfMedia (device
    // log: status=7 then nothing). 1.5s after EoM, if the hub has
    // not advanced by itself and the session is provably dead with
    // songs remaining, advance via the soak-proven next-button path.
    Timer {
        id: eomFallbackTimer
        interval: 1500
        repeat: false
        onTriggered: {
            // a. The hub advanced by itself - normal case, do nothing.
            if (hubPlaylist.currentIndex !== engine.eomArmedIndex) {
                return
            }
            // b. Session alive (e.g. repeat-one reloop) - NEVER
            // fight a live session.
            if (audio.playbackState === MediaPlayer.PlayingState) {
                return
            }
            // c. Natural end of the queue.
            if ((engine.queueStart + hubPlaylist.currentIndex + 1) >= engine.queue.length) {
                return
            }
            console.log('engine: eom fallback advanced the queue')
            engine.next()
        }
    }

    // --- Truth sampler: position-proof "is playing" ----------------
    // Always running. Position advancing past the last sample proves
    // audio regardless of what playbackState says; no advance plus a
    // non-PlayingState proves silence. Imperative Timer read, NOT a
    // declarative binding on audio.position (binding loops).
    Timer {
        id: playingTruthSampler
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            if (audio.position > 0 && audio.position > engine.lastSampledPos) {
                if (!engine.playing) {
                    console.log('engine: playing repaired by position proof pos=' + audio.position)
                }
                engine.playing = true
            } else if (audio.playbackState !== MediaPlayer.PlayingState) {
                engine.playing = false
            }
            engine.lastSampledPos = audio.position
        }
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

        onPlaybackStateChanged: {
            console.log('engine: playbackState=' + playbackState)
            // The late StoppedState teardown echo is known and
            // deliberately ignored: the UI truth is engine.playing,
            // and advancement is covered by the EndOfMedia fallback.
            // True direction only: a spurious StoppedState echo must
            // not freeze the UI, so no state here sets playing=false
            // - playingTruthSampler owns that.
            if (playbackState === MediaPlayer.PlayingState) {
                engine.playing = true
            }
            // Stop-then-commit gate: only a StoppedState answering
            // OUR stop request opens the commit. The flag is
            // consumed before commitQueue() runs, so StoppedState
            // echoes from our own stop/clear during commit are
            // ignored.
            if (playbackState === MediaPlayer.StoppedState && engine.awaitingStop) {
                engine.awaitingStop = false
                stopConfirmTimer.stop()
                console.log('engine: commit stopped confirmed')
                engine.commitQueue()
                return
            }
            if (playbackState === MediaPlayer.StoppedState
                    && !engine.warmingUp
                    && Date.now() - engine.lastCommitMs < 400) {
                // Late echo of the old session's teardown (sonic pattern):
                // re-play and re-arm the watchdog - NEVER pause() a live
                // session (the pause killed item 0, status=8, device log).
                // play() on a live session is harmless and re-emits
                // PlayingState, un-poisoning the property; if the session is
                // genuinely dead the watchdog escalates to pause+play itself.
                console.log('engine: late stop echo within commit window, re-arming')
                engine.playWithWatchdog()
                return
            }
        }
        onStatusChanged: {
            console.log('engine: status=' + status)
            // Arm the EndOfMedia fallback (never during warm-up).
            if (status === MediaPlayer.EndOfMedia && !engine.warmingUp) {
                engine.eomArmedIndex = hubPlaylist.currentIndex
                eomFallbackTimer.restart()
            }
        }

        // Observability only: a failed stream URL is otherwise
        // invisible - the playlist backend silently auto-advances
        // past the failed item and the watchdog "recovers" playback
        // of the wrong track. Policy (retry/skip) comes later, after
        // logs from a real run.
        onError: {
            console.log('engine: stream error code=' + error + ' string="' + errorString + '"')
        }

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
                console.log('engine: hubPlaylist.currentIndex -> ' + currentIndex +
                            ' playerIndex=' + ((engine.queueStart + currentIndex) % engine.queue.length))
                if (currentIndex < 0 || engine.rebuilding || engine.queue.length === 0) {
                    return
                }
                // The hub playlist is queue rotated by queueStart -
                // derive the UI position, never mirror the hub index.
                engine.playerIndex = (engine.queueStart + currentIndex) % engine.queue.length
            }
        }
    }
}
