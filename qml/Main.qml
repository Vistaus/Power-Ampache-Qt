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

    // SPIKE — session 2 playback smoke test: play the first cached song to
    // prove the stream path end to end. stats=0: a spike must NEVER record
    // a play. Session 3 replaces this with the real player flow, in which
    // queueManager owns all playback. Empty cache: skip silently.
    function runPlaybackSpike() {
        python.call('bridge.getFirstCachedSongId', [], function(result) {
            if (!result || !result.ok || !result.songId) {
                return
            }
            python.call('bridge.getStreamUrl', [result.songId, 0], function(urlResult) {
                if (!urlResult || !urlResult.ok) {
                    return
                }
                if (queueManager.currentIndex >= 0) {
                    // A real play already started; do not stomp it.
                    return
                }
                audio.source = urlResult.url
                audio.play()
            })
        })
    }

    PageStack {
        id: pageStack
    }

    Audio {
        id: audio
        // No auto-play: source is set only by the SPIKE or by queueManager.

        onStopped: {
            // Natural end advances the queue. Setting a new source also
            // stops playback, so gate strictly on EndOfMedia.
            if (status === MediaPlayer.EndOfMedia) {
                queueManager.next()
            }
        }
    }

    QtObject {
        id: queueManager

        // The ONE owner of play order. queue holds song dicts as returned
        // by bridge.getAlbumSongs (id, title, trackNumber, artistName,
        // albumId, albumName, time, imageUrl). Shuffle, repeat modes and
        // queue editing are session 3.
        property var queue: []
        property int currentIndex: -1
        readonly property var currentSong: (currentIndex >= 0 && currentIndex < queue.length) ? queue[currentIndex] : null
        readonly property bool playing: audio.playbackState === MediaPlayer.PlayingState

        // Core contract: tap in the middle of any list plays the whole
        // list from there (album now; playlists later).
        function playFrom(list, startIndex) {
            queue = list
            currentIndex = startIndex
            playCurrentSong()
        }

        function togglePlayPause() {
            if (audio.playbackState === MediaPlayer.PlayingState) {
                audio.pause()
            } else if (currentSong !== null) {
                audio.play()
            }
        }

        function next() {
            if (currentIndex < 0) {
                return
            }
            if (currentIndex + 1 < queue.length) {
                currentIndex = currentIndex + 1
                playCurrentSong()
            } else {
                // End of the queue: stop and clear the current song.
                audio.stop()
                currentIndex = -1
            }
        }

        function prev() {
            if (currentIndex > 0) {
                currentIndex = currentIndex - 1
                playCurrentSong()
            } else if (currentSong !== null) {
                // First track restarts via seek — re-fetching the URL with
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
            // plays feed the listen history. Only the SPIKE passes stats=0.
            // Never log result.url — it embeds the session token.
            python.call('bridge.getStreamUrl', [song.id], function(result) {
                if (result && result.ok) {
                    audio.source = result.url
                    audio.play()
                }
                // On failure leave the player stopped; session 3 owns error
                // surfacing.
            })
        }
    }

    // Now-playing mini-bar. Session 3: tapping it pushes the full player
    // page; for now it is display plus play/pause only.
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
            anchors {
                left: parent.left
                leftMargin: units.gu(2)
                right: playPauseIcon.left
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

        Icon {
            id: playPauseIcon
            anchors {
                right: parent.right
                rightMargin: units.gu(2)
                verticalCenter: parent.verticalCenter
            }
            width: units.gu(3)
            height: units.gu(3)
            name: queueManager.playing ? 'media-playback-pause' : 'media-playback-start'

            MouseArea {
                anchors.fill: parent
                onClicked: queueManager.togglePlayPause()
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
                    // SPIKE: session 2 smoke test — session 3 replaces it with the
                    // real player flow.
                    root.runPlaybackSpike()
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
                            text: i18n.tr('Offline — showing cached music')
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
                    bottomMargin: miniBar.visible ? miniBar.height : 0
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
