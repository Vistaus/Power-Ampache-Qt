/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7

// Mid-queue shuffle surgery, ut-sonic-player shuffleQueue()/resetQueue()
// pattern, adapted to this engine's queueStart-rotation invariant
// (hub item i === queue[(queueStart + i) % queue.length]).
//
// Passive by design: no timers, no Connections, no
// Component.onCompleted. Normal playback NEVER routes through this
// object - it exists solely for the opt-in, synchronous queue surgery
// while a track is playing. The hub playlist is NEVER cleared,
// currentIndex is NEVER assigned and play() is NEVER called here:
// the current item keeps playing while the rest of the playlist is
// rebuilt around it (device-proven in Sonic on this same media-hub
// backend).
//
// The platform's native Random playback mode is FORBIDDEN
// (qtubuntu-media pads it to forced looping, pad.lv/1518157) -
// visible queue surgery is the standard architecture for queue-based
// players.
Item {
    id: queueShuffler

    // Injected by Engine.qml at instantiation.
    property var engine
    property var hub

    // Log-once latch: queues committed before original-order capture
    // cannot be restored; do not spam the log on repeated toggles.
    property bool warnedNoOriginal: false

    // Full both-directions toggle. The shuffle flag ALWAYS flips
    // (eager shuffle at the next playFrom honors it); surgery is
    // skipped when the engine is in a state where it would be unsafe.
    function toggle() {
        engine.shuffle = !engine.shuffle
        if (engine.queue.length <= 1 || engine.playerIndex < 0
                || engine.warmingUp || engine.pendingCommit !== null
                || engine.awaitingStop || hub.currentIndex < 0) {
            console.log('queueShuffler: flag-only shuffle=' + engine.shuffle
                        + ' queue=' + engine.queue.length
                        + ' playerIndex=' + engine.playerIndex
                        + ' warmingUp=' + engine.warmingUp
                        + ' pendingCommit=' + (engine.pendingCommit !== null)
                        + ' awaitingStop=' + engine.awaitingStop)
            return
        }
        if (engine.queueUrls.length !== engine.queue.length) {
            // Parallel arrays desynced (pre-feature queue state):
            // surgery would build wrong URLs. Flag-only.
            console.log('queueShuffler: queueUrls out of sync, flag-only')
            return
        }
        if (engine.shuffle) {
            shuffleOn()
        } else {
            shuffleOff()
        }
    }

    // ON: current song stays hub item 0 and keeps playing; the rest
    // is Fisher-Yates shuffled behind it. New queue starts at the
    // current song (queueStart 0), matching Sonic shuffleQueue().
    function shuffleOn() {
        var current = engine.queue[engine.playerIndex]
        var pool = []
        for (var i = 0; i < engine.queue.length; i++) {
            if (i !== engine.playerIndex) pool.push(engine.queue[i])
        }
        for (var s = pool.length - 1; s > 0; s--) {
            var r = Math.floor(Math.random() * (s + 1))
            var tmp = pool[s]; pool[s] = pool[r]; pool[r] = tmp
        }
        var newQueue = [current].concat(pool)
        var map = urlMap()
        var newUrls = [map[String(current.id)]]
        for (var k = 0; k < pool.length; k++) {
            newUrls.push(map[String(pool[k].id)])
        }
        // Hub append = the shuffled rest (hub item 0 = current).
        surgeryCore(newQueue, newUrls, newUrls.slice(1), 0)
        console.log('queueShuffler: shuffle-on done count=' + newQueue.length)
    }

    // OFF: restore the original order captured at commit (BEFORE
    // eager shuffle), Sonic resetQueue pattern. The current song
    // keeps playing as hub item 0; the hub continues in true album
    // order behind it. Repeat != 'off' keeps the fresh-commit
    // rotation (tail + wrapped head); repeat 'off' stays tail-only.
    function shuffleOff() {
        if (engine.originalQueue.length === 0) {
            if (!warnedNoOriginal) {
                console.log('queueShuffler: no original order captured, restore skipped')
                warnedNoOriginal = true
            }
            return
        }
        var current = engine.queue[engine.playerIndex]
        var newIndex = -1
        for (var i = 0; i < engine.originalQueue.length; i++) {
            if (String(engine.originalQueue[i].id) === String(current.id)) {
                newIndex = i
                break
            }
        }
        if (newIndex < 0) {
            console.log('queueShuffler: current song not in original order, restore skipped')
            return
        }
        var newQueue = engine.originalQueue.slice()
        var map = urlMap()
        var newUrls = []
        for (var k = 0; k < newQueue.length; k++) {
            newUrls.push(map[String(newQueue[k].id)])
        }
        var after = newQueue.slice(newIndex + 1)
        var before = newQueue.slice(0, newIndex)
        var hubAppend = []
        for (var a = 0; a < after.length; a++) {
            hubAppend.push(map[String(after[a].id)])
        }
        if (engine.repeat !== 'off') {
            for (var b = 0; b < before.length; b++) {
                hubAppend.push(map[String(before[b].id)])
            }
        }
        surgeryCore(newQueue, newUrls, hubAppend, newIndex)
        console.log('queueShuffler: shuffle-off restore done index=' + newIndex)
    }

    // id -> stream URL for every song in the current queue. Reusing
    // stored URLs means NO refetch: the server never records a second
    // play stat for a shuffle toggle, and no async generation guard
    // is needed anywhere in this file.
    function urlMap() {
        var map = {}
        for (var i = 0; i < engine.queue.length; i++) {
            map[String(engine.queue[i].id)] = engine.queueUrls[i]
        }
        return map
    }

    // Sonic surgery, verbatim order: trim the hub to the current item
    // (remove after, then removeItem(0) x ci before it - removals
    // shift the playing item down to index 0, playback is
    // uninterrupted), then append the new rest. currentIndex is never
    // assigned and play() is never called.
    //
    // hubCount is DERIVED from the engine invariant, never read from
    // hub.itemCount (async and unreliable on media-hub): repeat 'off'
    // commits a tail-only playlist, everything else a full rotation.
    // Derived BEFORE the engine state below is replaced.
    function surgeryCore(newQueue, newUrls, hubAppendUrls, newQueueStart) {
        var hubCount = engine.repeat === 'off'
                ? engine.queue.length - engine.queueStart
                : engine.queue.length
        var ci = hub.currentIndex
        if (ci < 0) ci = 0
        console.log('queueShuffler: surgery ci=' + ci + ' hubCount=' + hubCount)
        engine.rebuilding = true
        while (hubCount > ci + 1) {
            hub.removeItem(hubCount - 1)
            hubCount--
        }
        for (var b = 0; b < ci; b++) {
            hub.removeItem(0)
        }
        if (hubAppendUrls.length > 0) {
            hub.addItems(hubAppendUrls)
        }
        engine.rebuilding = false
        // State replacement, engine invariant restored for the new
        // layout: hub item 0 = queue[newQueueStart] = current song.
        // playerIndex is set explicitly: the suppressed
        // onCurrentIndexChanged will not fire again after surgery.
        engine.queue = newQueue
        engine.queueUrls = newUrls
        engine.queueStart = newQueueStart
        engine.playerIndex = newQueueStart
        // The armed EndOfMedia fallback would fire on a stale hub
        // index after surgery: disarm.
        engine.eomArmedIndex = -2
    }
}
