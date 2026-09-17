/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7

// Mid-queue shuffle surgery, v2. The v1 Sonic-style surgery also
// removed entries BEFORE the playing one; device logs (phone AND
// desktop, 2026-09-17) prove that removal reloads the current
// HTTP stream - once = audible blip, twice inside one surgery =
// wedged hub, music stops. Sonic survives it because it plays
// local files; we stream, so v2 FORBIDS removing any entry at or
// before the playing one. The only hub mutations are removeItem
// AFTER current (backwards from the end) and addItems (append) -
// both seamless on both backends. The played history stays in
// front of current: unreachable forward under repeat 'off',
// walkable via prev(), cycled under repeat 'all'. After surgery
// the hub list IS the logical queue (queueStart 0).
//
// Passive by design: no timers, no Connections, no
// Component.onCompleted. Normal playback NEVER routes through
// this object. The platform Random playback mode stays forbidden
// (qtubuntu-media forces it to loop, pad.lv/1518157).
Item {
    id: queueShuffler

    // Injected by Engine.qml at instantiation.
    property var engine
    property var hub

    // Log-once latch: queues committed before original-order
    // capture cannot be restored; do not spam the log.
    property bool warnedNoOriginal: false

    // Full both-directions toggle. The shuffle flag ALWAYS flips
    // (eager shuffle at the next playFrom honors it); surgery is
    // skipped when the engine is in a state where it would be
    // unsafe.
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

    // Logical song at hub index j. The hub list is the queue
    // rotated by queueStart (repeat 'off' commits the tail, 'all'
    // the full rotation); the modulo covers the wrap.
    function hubFrom(j) {
        return engine.queue[(engine.queueStart + j) % engine.queue.length]
    }

    // id -> stream URL for every song in the current queue. Reusing
    // stored URLs means NO refetch: the server never records a
    // second play stat for a shuffle toggle.
    function urlMap() {
        var map = {}
        for (var i = 0; i < engine.queue.length; i++) {
            map[String(engine.queue[i].id)] = engine.queueUrls[i]
        }
        return map
    }

    // ON: current keeps playing where it is; everything after it in
    // the hub is replaced by a shuffle of ALL unplayed songs - the
    // hub entries after current PLUS, under repeat 'off', the
    // pre-tap head that the tail commit never put in the hub.
    // Index construction guarantees no overlap with the history
    // segment, so no dedup is needed here.
    function shuffleOn() {
        var ci = hub.currentIndex
        var pre = []
        for (var j = 0; j < ci; j++) {
            pre.push(hubFrom(j))
        }
        var current = hubFrom(ci)
        var hubCount = engine.repeat === 'off'
                ? engine.queue.length - engine.queueStart
                : engine.queue.length
        var pool = []
        if (engine.repeat === 'off') {
            // Pre-tap head: in the logical queue but not in the hub.
            for (var h = 0; h < engine.queueStart; h++) {
                pool.push(engine.queue[h])
            }
        }
        for (var a = ci + 1; a < hubCount; a++) {
            pool.push(hubFrom(a))
        }
        for (var s = pool.length - 1; s > 0; s--) {
            var r = Math.floor(Math.random() * (s + 1))
            var tmp = pool[s]; pool[s] = pool[r]; pool[r] = tmp
        }
        buildCommit(pre, current, pool)
        console.log('queueShuffler: shuffle-on done history=' + pre.length
                    + ' rest=' + pool.length)
    }

    // OFF: restore the original order FROM THE CURRENT SONG ONWARD
    // (the played history in front stays as-is). Songs already in
    // the history are not re-added to the rest: under repeat 'all'
    // the cycle reaches them through the history segment instead.
    // Accepted edge: a playlist containing the same song twice can
    // dedup both copies (id-based check).
    function shuffleOff() {
        if (engine.originalQueue.length === 0) {
            if (!warnedNoOriginal) {
                console.log('queueShuffler: no original order captured, restore skipped')
                warnedNoOriginal = true
            }
            return
        }
        var ci = hub.currentIndex
        var pre = []
        var preIds = {}
        for (var j = 0; j < ci; j++) {
            var played = hubFrom(j)
            pre.push(played)
            preIds[String(played.id)] = true
        }
        var current = hubFrom(ci)
        preIds[String(current.id)] = true
        var oi = -1
        for (var i = 0; i < engine.originalQueue.length; i++) {
            if (String(engine.originalQueue[i].id) === String(current.id)) {
                oi = i
                break
            }
        }
        if (oi < 0) {
            console.log('queueShuffler: current song not in original order, restore skipped')
            return
        }
        var rest = []
        for (var k = oi + 1; k < engine.originalQueue.length; k++) {
            var song = engine.originalQueue[k]
            if (!preIds[String(song.id)]) {
                rest.push(song)
            }
        }
        if (engine.repeat !== 'off') {
            for (var w = 0; w < oi; w++) {
                var wrapped = engine.originalQueue[w]
                if (!preIds[String(wrapped.id)]) {
                    rest.push(wrapped)
                }
            }
        }
        buildCommit(pre, current, rest)
        console.log('queueShuffler: shuffle-off restore done originalIndex=' + oi
                    + ' history=' + pre.length + ' rest=' + rest.length)
    }

    // Assemble and commit the new logical queue: history, then the
    // current song, then the new rest. newQueue and newUrls are
    // parallel by construction; every URL comes from urlMap(), so
    // no song ever changes its stream URL (no stats double-count).
    function buildCommit(pre, current, rest) {
        var map = urlMap()
        var newQueue = pre.slice()
        var newUrls = []
        var i
        for (i = 0; i < pre.length; i++) {
            newUrls.push(map[String(pre[i].id)])
        }
        newQueue.push(current)
        newUrls.push(map[String(current.id)])
        for (i = 0; i < rest.length; i++) {
            newQueue.push(rest[i])
            newUrls.push(map[String(rest[i].id)])
        }
        surgeryCore(newQueue, newUrls)
    }

    // The ONLY hub-mutating function. Removes everything AFTER the
    // playing entry (backwards from the end - proven safe on both
    // backends), appends the new rest, then swaps the logical state
    // so the hub list and engine.queue are one and the same
    // (queueStart 0). NEVER touches entries at or before current:
    // v1 did and the backend reloaded the stream (device-proven).
    function surgeryCore(newQueue, newUrls) {
        var ci = hub.currentIndex
        var hubCount = engine.repeat === 'off'
                ? engine.queue.length - engine.queueStart
                : engine.queue.length
        console.log('queueShuffler: surgery ci=' + ci + ' hubCount=' + hubCount)
        engine.rebuilding = true
        while (hubCount > ci + 1) {
            hub.removeItem(hubCount - 1)
            hubCount--
        }
        if (newUrls.length > ci + 1) {
            hub.addItems(newUrls.slice(ci + 1))
        }
        engine.rebuilding = false
        // hub item j === newQueue[j] now: queueStart 0, playerIndex
        // = the current song's new logical index = ci (nothing
        // moved the playing entry). onCurrentIndexChanged stays
        // suppressed; playerIndex is set explicitly.
        engine.queue = newQueue
        engine.queueUrls = newUrls
        engine.queueStart = 0
        engine.playerIndex = ci
        // The armed EndOfMedia fallback would fire on a stale hub
        // index after surgery: disarm.
        engine.eomArmedIndex = -2
    }
}
