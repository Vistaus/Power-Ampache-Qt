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

    // Now-playing mini-bar: prev / play-pause / next; tapping the
    // title/artist area pushes the full player page.
    Rectangle {
        id: miniBar
        visible: queueManager.currentSong !== null
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: units.gu(6)
        color: theme.palette.normal.base

        Column {
            id: miniBarText
            anchors {
                left: parent.left
                leftMargin: units.gu(2)
                right: miniBarControls.left
                rightMargin: units.gu(1)
                verticalCenter: parent.verticalCenter
            }

            Label {
                width: parent.width
                text: queueManager.currentSong !== null ? queueManager.currentSong.title : ''
                font.bold: true
                elide: Text.ElideRight
            }

            Label {
                width: parent.width
                text: queueManager.currentSong !== null ? queueManager.currentSong.artistName : ''
                fontSize: 'small'
                elide: Text.ElideRight
            }
        }

        // Tap target that opens the player page: everything left of the
        // controls.
        MouseArea {
            anchors {
                left: parent.left
                top: parent.top
                bottom: parent.bottom
                right: miniBarControls.left
            }
            onClicked: {
                // Guard against stacking a second player page.
                if (pageStack.currentPage.objectName !== 'playerPage') {
                    pageStack.push(playerPageComponent)
                }
            }
        }

        Row {
            id: miniBarControls
            anchors {
                right: parent.right
                rightMargin: units.gu(2)
                verticalCenter: parent.verticalCenter
            }
            spacing: units.gu(2)

            Icon {
                width: units.gu(3)
                height: units.gu(3)
                name: 'media-skip-backward'

                MouseArea {
                    anchors.fill: parent
                    onClicked: queueManager.prev()
                }
            }

            Icon {
                width: units.gu(3)
                height: units.gu(3)
                name: queueManager.playing ? 'media-playback-pause' : 'media-playback-start'

                MouseArea {
                    anchors.fill: parent
                    onClicked: queueManager.togglePlayPause()
                }
            }

            Icon {
                width: units.gu(3)
                height: units.gu(3)
                name: 'media-skip-forward'

                MouseArea {
                    anchors.fill: parent
                    onClicked: queueManager.next()
                }
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

        Page {
            header: PageHeader {
                id: pageHeader
                title: i18n.tr('Power Ampache')
            }

            Column {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: pageHeader.bottom
                    margins: units.gu(4)
                }
                spacing: units.gu(2)

                Label {
                    width: parent.width
                    text: i18n.tr('Connect to your Ampache server')
                }

                TextField {
                    id: serverField
                    width: parent.width
                    placeholderText: i18n.tr('Server URL')
                    inputMethodHints: Qt.ImhUrlCharactersOnly
                }

                TextField {
                    id: usernameField
                    width: parent.width
                    placeholderText: i18n.tr('Username')
                }

                TextField {
                    id: passwordField
                    width: parent.width
                    placeholderText: i18n.tr('Password')
                    echoMode: TextInput.Password
                }

                Label {
                    id: loginErrorLabel
                    width: parent.width
                    visible: text !== ''
                    wrapMode: Text.Wrap
                    color: LomiriColors.red
                }

                Button {
                    id: connectButton
                    width: parent.width
                    color: LomiriColors.green
                    text: i18n.tr('Connect')

                    onClicked: {
                        loginErrorLabel.text = ''
                        connectButton.enabled = false
                        python.call('bridge.storeCredentials',
                                [serverField.text, usernameField.text, passwordField.text],
                                function(storeResult) {
                            if (!storeResult || !storeResult.ok) {
                                connectButton.enabled = true
                                loginErrorLabel.text = i18n.tr('Could not save credentials')
                                return
                            }
                            python.call('bridge.authenticate', [], function(authResult) {
                                connectButton.enabled = true
                                if (authResult && authResult.ok) {
                                    root.justAuthenticated = true
                                    passwordField.text = ''
                                    pageStack.clear()
                                    pageStack.push(homePageComponent)
                                } else if (authResult && authResult.errorKind === 'credentials') {
                                    loginErrorLabel.text = i18n.tr('Wrong username or password')
                                } else if (authResult && authResult.errorKind === 'offline') {
                                    loginErrorLabel.text = i18n.tr('Server unreachable')
                                } else {
                                    loginErrorLabel.text = i18n.tr('Connection failed')
                                }
                            })
                        })
                    }
                }
            }
        }
    }

    Component {
        id: homePageComponent

        Page {
            header: PageHeader {
                id: pageHeader
                title: i18n.tr('Power Ampache')
            }

            Flickable {
                id: homeFlickable
                anchors {
                    top: pageHeader.bottom
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                contentWidth: width
                contentHeight: homeColumn.implicitHeight
                clip: true

                Column {
                    id: homeColumn
                    width: homeFlickable.width
                    spacing: units.gu(2)

                    Rectangle {
                        id: offlineBanner
                        visible: false
                        width: parent.width
                        height: units.gu(4)
                        color: LomiriColors.orange

                        Label {
                            anchors.centerIn: parent
                            text: i18n.tr('Offline - showing cached music')
                        }
                    }

                    Repeater {
                        id: sectionRepeater
                        model: [
                            { title: i18n.tr('Recently played'),   functionName: 'bridge.getRecentAlbums' },
                            { title: i18n.tr('Favourites'),        functionName: 'bridge.getFavouriteAlbums' },
                            { title: i18n.tr('Frequently played'), functionName: 'bridge.getFrequentAlbums' },
                            { title: i18n.tr('Highest rated'),     functionName: 'bridge.getHighestAlbums' },
                            { title: i18n.tr('Newly added'),       functionName: 'bridge.getNewestAlbums' },
                            { title: i18n.tr('Random'),            functionName: 'bridge.getRandomAlbums' }
                        ]
                        delegate: albumRowComponent
                    }
                }
            }

            Component.onCompleted: {
                // Background auth: failure must not interrupt browsing.
                // Skip when the login flow just authenticated; reset the
                // flag so a later cold start still authenticates.
                if (root.justAuthenticated) {
                    root.justAuthenticated = false
                } else {
                    python.call('bridge.authenticate', [], function(authResult) {
                        if (authResult && !authResult.ok && authResult.errorKind === 'offline') {
                            offlineBanner.visible = true
                        }
                    })
                }
                // Fire all six fetches at once; each row renders as its
                // data arrives. Favourites answers from the local DB.
                for (var i = 0; i < sectionRepeater.model.length; i++) {
                    loadRow(i, sectionRepeater.model[i].functionName)
                }
            }

            function loadRow(rowIndex, functionName) {
                python.call(functionName, [], function(result) {
                    if (result && result.ok) {
                        var row = sectionRepeater.itemAt(rowIndex)
                        for (var i = 0; i < result.albums.length; i++) {
                            row.model.append(result.albums[i])
                        }
                    } else if (result && result.errorKind === 'offline') {
                        offlineBanner.visible = true
                    }
                    // Any other failure: the row stays empty and hidden.
                })
            }
        }
    }

    Component {
        id: albumPageComponent

        Page {
            id: albumPage
            property var albumId
            property string albumName: ''
            // Tracks in the order the bridge returns them; this same array
            // is handed to queueManager.playFrom() on track tap.
            property var tracks: []

            header: PageHeader {
                id: albumPageHeader
                title: albumPage.albumName
            }

            ListView {
                id: trackListView
                anchors {
                    top: albumPageHeader.bottom
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                clip: true
                model: albumPage.tracks

                delegate: Item {
                    width: trackListView.width
                    height: units.gu(6)

                    Label {
                        id: trackNumberLabel
                        anchors {
                            left: parent.left
                            leftMargin: units.gu(2)
                            verticalCenter: parent.verticalCenter
                        }
                        width: units.gu(3)
                        text: modelData.trackNumber
                    }

                    Column {
                        anchors {
                            left: trackNumberLabel.right
                            leftMargin: units.gu(1)
                            right: durationLabel.left
                            rightMargin: units.gu(1)
                            verticalCenter: parent.verticalCenter
                        }

                        Label {
                            width: parent.width
                            text: modelData.title
                            elide: Text.ElideRight
                        }

                        Label {
                            width: parent.width
                            text: modelData.artistName
                            fontSize: 'small'
                            elide: Text.ElideRight
                        }
                    }

                    Label {
                        id: durationLabel
                        anchors {
                            right: parent.right
                            rightMargin: units.gu(2)
                            verticalCenter: parent.verticalCenter
                        }
                        text: root.formatDuration(modelData.time)
                        fontSize: 'small'
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: queueManager.playFrom(albumPage.tracks, index)
                    }
                }
            }

            Component.onCompleted: {
                python.call('bridge.getAlbumSongs', [albumPage.albumId], function(result) {
                    if (result && result.ok) {
                        albumPage.tracks = result.songs
                    }
                    // On failure the page stays empty; session 3 owns error
                    // surfacing.
                })
            }
        }
    }

    Component {
        id: playerPageComponent

        Page {
            id: playerPage
            objectName: 'playerPage'

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
                if (queueManager.currentSong === null) {
                    setLyricsSection(false)
                    return
                }
                python.call('bridge.getLyrics', [queueManager.currentSong.id], function(result) {
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
                            source: queueManager.currentSong !== null ? queueManager.currentSong.imageUrl : ''
                            visible: queueManager.currentSong !== null && queueManager.currentSong.imageUrl !== ''
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }

                        Icon {
                            anchors.centerIn: parent
                            width: units.gu(8)
                            height: units.gu(8)
                            name: 'stock_music'
                            visible: queueManager.currentSong === null || queueManager.currentSong.imageUrl === ''
                        }
                    }

                    Label {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: queueManager.currentSong !== null ? queueManager.currentSong.title : ''
                        fontSize: 'large'
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Label {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: queueManager.currentSong !== null ? queueManager.currentSong.artistName : ''
                        elide: Text.ElideRight
                    }

                    Label {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: queueManager.currentSong !== null ? queueManager.currentSong.albumName : ''
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
                            maximumValue: audio.duration > 0 ? audio.duration : 1
                            value: audio.position
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
                            // bindings on audio.position/duration caused
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
                                onClicked: queueManager.prev()
                            }
                        }

                        Icon {
                            width: units.gu(6)
                            height: units.gu(6)
                            name: queueManager.playing ? 'media-playback-pause' : 'media-playback-start'

                            MouseArea {
                                anchors.fill: parent
                                onClicked: queueManager.togglePlayPause()
                            }
                        }

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: units.gu(4)
                            height: units.gu(4)
                            name: 'media-skip-forward'

                            MouseArea {
                                anchors.fill: parent
                                onClicked: queueManager.next()
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
                            opacity: queueManager.shuffle ? 1.0 : 0.3

                            MouseArea {
                                anchors.fill: parent
                                onClicked: queueManager.toggleShuffle()
                            }
                        }

                        Icon {
                            width: units.gu(3)
                            height: units.gu(3)
                            name: queueManager.repeat === 'one' ? 'media-playlist-repeat-one' : 'media-playlist-repeat'
                            opacity: queueManager.repeat === 'off' ? 0.3 : 1.0

                            MouseArea {
                                anchors.fill: parent
                                onClicked: queueManager.cycleRepeat()
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
                model: queueManager.queue

                delegate: Item {
                    width: queueListView.width
                    height: units.gu(6)

                    Rectangle {
                        anchors.fill: parent
                        color: index === queueManager.currentIndex
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
                            font.bold: index === queueManager.currentIndex
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
                        onClicked: queueManager.playFrom(queueManager.queue, index)
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
                running: audio.playbackState === MediaPlayer.PlayingState
                onTriggered: {
                    // audio.position/duration are ms; formatDuration
                    // takes seconds.
                    positionLabel.text = root.formatDuration(audio.position / 1000)
                    durationLabel.text = root.formatDuration(audio.duration / 1000)
                }
            }

            Component.onCompleted: {
                // Page (re)opened with a track already loaded but paused:
                // seed current values so the labels are never blank.
                positionLabel.text = root.formatDuration(audio.position / 1000)
                durationLabel.text = root.formatDuration(audio.duration / 1000)
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
                target: queueManager
                onCurrentSongChanged: {
                    // Reset the clock so a fresh/stopped track never shows
                    // the previous track's times. Uses the song's own
                    // duration (seconds) so a paused track shows 0:00 /
                    // its length before the stream reports a duration.
                    positionLabel.text = root.formatDuration(0)
                    durationLabel.text = root.formatDuration(
                        queueManager.currentSong !== null ? queueManager.currentSong.time : 0)
                    if (playerPageHeader.sections.selectedIndex === 2) {
                        playerPage.loadLyrics()
                    }
                }
            }
        }
    }

    Component {
        id: albumRowComponent

        Item {
            id: albumRow
            property alias model: albumModel

            // Empty rows are omitted: the Column skips invisible children.
            visible: albumModel.count > 0
            width: parent.width
            height: rowLabel.height + albumListView.height + units.gu(1)

            ListModel {
                id: albumModel
            }

            Label {
                id: rowLabel
                anchors {
                    left: parent.left
                    top: parent.top
                    leftMargin: units.gu(2)
                }
                text: modelData.title
                fontSize: 'large'
            }

            ListView {
                id: albumListView
                anchors {
                    left: parent.left
                    right: parent.right
                    top: rowLabel.bottom
                    topMargin: units.gu(1)
                    leftMargin: units.gu(2)
                }
                height: units.gu(22)
                orientation: ListView.Horizontal
                spacing: units.gu(1)
                clip: true
                model: albumModel

                delegate: Item {
                    width: units.gu(16)
                    height: albumListView.height

                    Rectangle {
                        id: coverFrame
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                        }
                        height: width
                        color: theme.palette.normal.base

                        Image {
                            anchors.fill: parent
                            source: artUrl
                            visible: artUrl !== ''
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }

                        Icon {
                            anchors.centerIn: parent
                            width: units.gu(6)
                            height: units.gu(6)
                            name: 'stock_music'
                            visible: artUrl === ''
                        }
                    }

                    Column {
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: coverFrame.bottom
                            topMargin: units.gu(0.5)
                        }
                        spacing: units.gu(0.2)

                        Label {
                            width: parent.width
                            text: name
                            fontSize: 'small'
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Label {
                            width: parent.width
                            text: artistName
                            fontSize: 'small'
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: pageStack.push(albumPageComponent, { albumId: model.id, albumName: model.name })
                    }
                }
            }
        }
    }

    Component {
        id: errorPageComponent

        Page {
            property string message: i18n.tr('Could not open the local database')

            header: PageHeader {
                title: i18n.tr('Power Ampache')
            }

            Label {
                anchors.centerIn: parent
                text: message
            }
        }
    }
}
