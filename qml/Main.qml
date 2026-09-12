/*
 * Copyright (C) 2026  icefields
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 3.
 *
 * powerampache is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick 2.7
import Lomiri.Components 1.3
import io.thp.pyotherside 1.4
import QtMultimedia 5.0
import "pages"
import "components"

MainView {
    id: root
    objectName: 'mainView'
    applicationName: 'powerampache.icefields'

    width: units.gu(45)
    height: units.gu(75)

    property bool justAuthenticated: false

    function formatDuration(totalSeconds) {
        var seconds = Math.max(0, Math.floor(totalSeconds))
        var minutes = Math.floor(seconds / 60)
        var remainder = seconds % 60
        return minutes + ':' + (remainder < 10 ? '0' : '') + remainder
    }

    PageStack {
        id: pageStack
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            bottom: parent.bottom
            // The ONE reservation for the mini-bar: every page in the
            // stack ends above the bar. Per-view bottomMargin lines are
            // forbidden from now on - this owns it.
            bottomMargin: miniBar.visible ? miniBar.height : 0
        }
    }

    Audio {
        id: audio
        // No auto-play: source is set only by queueManager.

        onStopped: {
            // Natural end goes through queueManager.onNaturalEnd() (repeat
            // 'one' replays there, and ONLY there). Setting a new source
            // also stops playback, so gate strictly on EndOfMedia.
            if (status === MediaPlayer.EndOfMedia) {
                queueManager.onNaturalEnd()
            }
        }
    }

    // Watchdog for the device-only media-hub first-play swallow: the hub
    // session drops play() until a pause() has primed its state machine.
    // 2s after every play() we check whether playback actually advanced.
    Timer {
        id: playWatchdog
        interval: 2000
        onTriggered: queueManager.playWatchdogCheck()
    }

    // The kick itself: pause() then play(), the sequence proven to work
    // manually. 1000ms gap - replicates the twice-proven manual gap from
    // the device logs; shorter may race the hub's pause state transition.
    Timer {
        id: playKick
        interval: 1000
        onTriggered: audio.play()
    }

    QtObject {
        id: queueManager

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
            python.call('bridge.getStreamUrl', [song.id], function(result) {
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

    MiniBar {
        id: miniBar
        playback: queueManager
        openPlayerCallback: function() {
            // Guard against stacking a second player page.
            if (pageStack.currentPage.objectName !== 'playerPage') {
                pageStack.push(playerPageComponent)
            }
        }
    }

    Python {
        id: python

        Component.onCompleted: {
            addImportPath(Qt.resolvedUrl('../src/'))
            importModule('bridge', function() {
                python.call('bridge.init', [], function(initResult) {
                    if (!initResult || !initResult.ok) {
                        pageStack.push(errorPageComponent)
                        return
                    }
                    python.call('bridge.hasCredentials', [], function(credentialsResult) {
                        if (credentialsResult.ok && credentialsResult.hasCredentials) {
                            pageStack.push(homePageComponent)
                        } else {
                            pageStack.push(loginPageComponent)
                        }
                    })
                })
            })
        }

        onError: {
            console.log('python error: ' + traceback)
            pageStack.clear()
            pageStack.push(errorPageComponent, { message: i18n.tr('Internal error') })
        }
    }

    Component {
        id: loginPageComponent

        LoginPage {
            pythonBridge: python
            authenticatedCallback: function() {
                root.justAuthenticated = true
                pageStack.clear()
                pageStack.push(homePageComponent)
            }
        }
    }

    Component {
        id: homePageComponent

        HomePage {
            pythonBridge: python
            mainView: root
            albumRowDelegate: albumRowComponent
        }
    }

    Component {
        id: albumPageComponent

        AlbumPage {
            pythonBridge: python
            playback: queueManager
            formatDuration: root.formatDuration
        }
    }

    Component {
        id: playerPageComponent

        PlayerPage {
            playback: queueManager
            pythonBridge: python
            audioEngine: audio
            formatDuration: root.formatDuration
        }
    }

    Component {
        id: albumRowComponent

        AlbumRow {
            openAlbumCallback: function(albumId, albumName) {
                pageStack.push(albumPageComponent, {
                    albumId: albumId, albumName: albumName
                })
            }
        }
    }

    Component {
        id: errorPageComponent
        ErrorPage { }
    }
}
