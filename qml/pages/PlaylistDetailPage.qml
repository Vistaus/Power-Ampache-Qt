/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3
import "../components"

// Playlist drill-down: track list, tap plays the playlist from that
// track. playlistId and playlistName arrive via push-with-properties
// (the Component wrapper in Main.qml makes them land here).
// pythonBridge (the Python element), playback (the queue manager)
// and formatDuration are injected at the use site.
Page {
    id: playlistDetailPage

    property var playlistId
    property string playlistName: ''
    property var pythonBridge
    property var playback
    property var formatDuration

    // Tracks in playlist-position order exactly as the bridge
    // returns them; never re-sort. This same array is handed to
    // queueManager.playFrom() on track tap.
    property var tracks: []

    header: PageHeader {
        id: playlistDetailHeader
        title: playlistDetailPage.playlistName
    }

    ListView {
        id: trackListView
        anchors {
            top: playlistDetailHeader.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        clip: true
        model: playlistDetailPage.tracks

        delegate: TrackDelegate {
            width: trackListView.width
            playTrackCallback: function(rowIndex) {
                playback.playFrom(playlistDetailPage.tracks, rowIndex)
            }
            formatDuration: playlistDetailPage.formatDuration
        }
    }

    Component.onCompleted: {
        pythonBridge.call('bridge.getPlaylistSongs', [playlistDetailPage.playlistId], function(result) {
            if (result && result.ok) {
                playlistDetailPage.tracks = result.songs
            }
            // On failure the page stays empty; session 3 owns error
            // surfacing.
        })
    }
}
