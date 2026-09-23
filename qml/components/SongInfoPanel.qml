/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3

// Song info panel: album cover plus the current song's metadata
// rows, read from the local cache via bridge.getSongInfo (direct
// sqlite, no network). Loads itself when it becomes visible and on
// song change while visible - a local read is cheap, so no
// expanded-state gating is needed. playback, pythonBridge,
// formatDuration and overlayRoot (the PlayerOverlay, null on the
// page player) are injected at the use site; anchors and visibility
// are set there too.
Flickable {
    id: songInfoFlickable

    property var playback
    property var pythonBridge
    property var formatDuration
    property var overlayRoot

    property var infoRows: []

    contentWidth: width
    contentHeight: infoColumn.height + units.gu(4)
    clip: true

    // Pull-to-dismiss wiring: forward top-overshoot to the overlay
    // sheet (PlayerOverlay overscrollPull/Release/Retract). Dragging
    // down while already at the top drags the sheet instead; normal
    // scrolling is untouched. Null-guarded: inert on the page player.
    boundsBehavior: Flickable.DragAndOvershootBounds
    onContentYChanged: {
        if (!overlayRoot) {
            return
        }
        if (contentY < 0) {
            overlayRoot.overscrollPull(-contentY)
        } else {
            overlayRoot.overscrollRetract()
        }
    }
    onDraggingChanged: {
        if (!dragging && overlayRoot) {
            overlayRoot.overscrollRelease(contentY < 0 ? -contentY : 0)
        }
    }
    onMovementEnded: {
        // Safety net: if the dragging signal never fired (platform
        // quirk), the rebound's end still settles a followed sheet.
        if (overlayRoot && contentY >= 0) {
            overlayRoot.overscrollRelease(0)
        }
    }

    function load() {
        if (playback.currentSong === null) {
            infoRows = []
            return
        }
        pythonBridge.call('bridge.getSongInfo', [playback.currentSong.id], function(result) {
            if (!result || !result.ok || result.info === null) {
                infoRows = []
                return
            }
            var info = result.info
            var rows = []
            function add(label, value) {
                if (value !== '' && value !== null && value !== undefined) {
                    rows.push({ label: label, value: String(value) })
                }
            }
            add(i18n.tr('Title'), info.title)
            add(i18n.tr('Artist'), info.artistName)
            add(i18n.tr('Album'), info.albumName)
            add(i18n.tr('Album artist'), info.albumArtist)
            add(i18n.tr('Genre'), info.genre)
            if (info.year > 0) {
                add(i18n.tr('Year'), info.year)
            }
            if (info.trackNumber > 0) {
                add(i18n.tr('Track'), info.trackNumber)
            }
            if (info.disk > 0) {
                add(i18n.tr('Disk'), info.disk)
            }
            if (info.time > 0) {
                add(i18n.tr('Duration'), formatDuration(info.time))
            }
            if (info.bitrate > 0) {
                // Bitrate is stored bits/sec; display kbps.
                add(i18n.tr('Bitrate'), Math.round(info.bitrate / 1000) + ' kbps')
            }
            if (info.rateHz > 0) {
                add(i18n.tr('Sample rate'), (info.rateHz / 1000).toFixed(1) + ' kHz')
            }
            if (info.channels > 0) {
                add(i18n.tr('Channels'),
                    info.channels === 1 ? 'Mono'
                    : (info.channels === 2 ? 'Stereo' : String(info.channels)))
            }
            if (info.size > 0) {
                add(i18n.tr('File size'), (info.size / 1048576).toFixed(1) + ' MB')
            }
            add(i18n.tr('Format'), info.format)
            add(i18n.tr('Composer'), info.composer)
            if (info.playCount > 0) {
                add(i18n.tr('Play count'), info.playCount)
            }
            if (info.rating > 0) {
                add(i18n.tr('Rating'), info.rating)
            }
            add(i18n.tr('Language'), info.language)
            add(i18n.tr('Comment'), info.comment)
            add(i18n.tr('Publisher'), info.publisher)
            add(i18n.tr('MusicBrainz ID'), info.mbId)
            if (info.replayGainTrackGain !== null
                    && info.replayGainTrackGain !== undefined
                    && info.replayGainTrackGain !== 0) {
                add(i18n.tr('Replay gain'), info.replayGainTrackGain + ' dB')
            }
            infoRows = rows
        })
    }

    onVisibleChanged: {
        // Lazy load: becoming visible (tab selected / overlay
        // reopened) refreshes from the local cache.
        if (visible) {
            load()
        }
    }

    Connections {
        target: playback
        onCurrentSongChanged: {
            // Cheap local read: refresh in place while visible.
            if (songInfoFlickable.visible) {
                songInfoFlickable.load()
            }
        }
    }

    Column {
        id: infoColumn
        x: units.gu(2)
        width: songInfoFlickable.width - units.gu(4)
        spacing: units.gu(2)

        Item { width: 1; height: units.gu(2) }

        Item {
            // Full-bleed cover: spans the whole panel width, edge
            // to edge. The column only manages vertical layout, so a
            // wider child with an explicit x is respected; x cancels
            // the column's 2gu inset to reach the panel's left edge.
            width: songInfoFlickable.width
            x: -units.gu(2)
            height: width

            Rectangle {
                id: infoCoverFrame
                anchors.fill: parent
                color: theme.palette.normal.base

                Image {
                    anchors.fill: parent
                    source: playback.currentSong !== null ? playback.currentSong.imageUrl : ''
                    visible: playback.currentSong !== null && playback.currentSong.imageUrl !== ''
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }

                Icon {
                    anchors.centerIn: parent
                    width: units.gu(8)
                    height: units.gu(8)
                    name: 'stock_music'
                    visible: playback.currentSong === null || playback.currentSong.imageUrl === ''
                }
            }
        }

        Repeater {
            model: songInfoFlickable.infoRows

            Column {
                width: infoColumn.width
                spacing: units.gu(0.3)

                Label {
                    width: parent.width
                    text: modelData.label
                    fontSize: 'small'
                    opacity: 0.6
                    elide: Text.ElideRight
                }

                Label {
                    width: parent.width
                    text: modelData.value
                    wrapMode: Text.Wrap
                }
            }
        }

        Item { width: 1; height: units.gu(2) }
    }
}
