/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3
import "../components"

// Album drill-down: track list, tap plays the album from that track.
// albumId and albumName arrive via push-with-properties (the Component
// wrapper in Main.qml makes them land here). pythonBridge (the Python
// element), playback (the queue manager) and formatDuration are
// injected at the use site.
Page {
    id: albumPage

    property var albumId
    property string albumName: ''
    property var pythonBridge
    property var playback
    property var formatDuration

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

        delegate: TrackDelegate {
            width: trackListView.width
            playTrackCallback: function(rowIndex) {
                playback.playFrom(albumPage.tracks, rowIndex)
            }
            formatDuration: albumPage.formatDuration
        }
    }

    Component.onCompleted: {
        pythonBridge.call('bridge.getAlbumSongs', [albumPage.albumId], function(result) {
            if (result && result.ok) {
                albumPage.tracks = result.songs
            }
            // On failure the page stays empty; session 3 owns error
            // surfacing.
        })
    }
}
