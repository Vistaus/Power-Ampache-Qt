/*
 * SPDX-FileCopyrightText: 2026 icefields
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick 2.7
import Lomiri.Components 1.3

// Global bottom navigation bar. Main.qml shows it only in single-column
// mode post-login; in 2-column mode the Library auto-mounts into
// column 1 instead (see maybeMountLibrary).
Item {
    id: navBar
    objectName: 'navBar'

    // Injected at the use site.
    property var pageLayout
    property var libraryPageComponent
    property var albumPageComponent
    property var playerPageComponent
    property var playlistDetailPageComponent
    property bool wideMode

    // Instance/incubator tracking: pages cannot be reused, only
    // Components.
    property var libraryPageInstance: null
    property var albumPageInstance: null
    property var playerPageInstance: null
    property var libraryIncubator: null
    property var albumIncubator: null
    property var playerIncubator: null
    // Retry budget for rejected column-1 Library mounts (startup race
    // against APL primary-page registration).
    property int libraryMountRetries: 0

    // Birth-mode tracking: whether each page was created while the
    // layout was already two-column. Single-born pages stay in the
    // primary page's column-0 subtree when the layout grows and must
    // be migrated (removed + reopened); wide-born pages are APL's
    // business.
    property bool libraryBirthWide: false
    property bool albumBirthWide: false
    property bool playerBirthWide: false

    // Migration state for the single-to-two-column transition.
    property string pendingReopen: ''   // '', 'player', 'album', 'library'
    property var pendingAlbumId: null
    property string pendingAlbumName: ''

    height: units.gu(7)

    function homeTapped() {
        pageLayout.removePages(pageLayout.primaryPage)
    }

    function libraryTapped() {
        // Jump to a fresh Library root; the old stack above it is
        // discarded.
        if (libraryPageInstance === null) {
            openLibrary()
        } else {
            pageLayout.removePages(libraryPageInstance)
            openLibrary()
        }
    }

    function openLibrary() {
        var incubator = pageLayout.addPageToCurrentColumn(
            pageLayout.primaryPage, libraryPageComponent)
        if (incubator) {
            libraryIncubator = incubator
            incubator.onStatusChanged = function(status) {
                if (status === Component.Ready) {
                    libraryPageInstance = incubator.object
                    libraryBirthWide = false
                    incubator.object.Component.destruction.connect(function() {
                        libraryPageInstance = null
                        libraryBirthWide = false
                    })
                    libraryIncubator = null
                } else if (status === Component.Error) {
                    libraryIncubator = null
                }
            }
        }
    }

    function mountLibraryDefault() {
        console.log('navBar: mountLibraryDefault wideMode=' + wideMode)
        // The 2-column desktop mount: Library lives in column 1.
        var incubator = pageLayout.addPageToNextColumn(
            pageLayout.primaryPage, libraryPageComponent)
        if (incubator) {
            libraryIncubator = incubator
            incubator.onStatusChanged = function(status) {
                if (status === Component.Ready) {
                    libraryMountRetries = 0
                    libraryPageInstance = incubator.object
                    libraryBirthWide = true
                    incubator.object.Component.destruction.connect(function() {
                        libraryPageInstance = null
                        libraryBirthWide = false
                    })
                    libraryIncubator = null
                } else if (status === Component.Error) {
                    libraryIncubator = null
                }
            }
        } else {
            // APL rejected the add (primary page not yet registered in
            // its tree). Retry via the 300ms restore timer, capped.
            console.log('navBar: mountLibraryDefault rejected, retry '
                + libraryMountRetries)
            if (libraryMountRetries < 20) {
                libraryMountRetries = libraryMountRetries + 1
                scheduleCol1Restore()
            }
        }
    }

    function openAlbum(albumId, albumName) {
        console.log('navBar: openAlbum wideMode=' + wideMode)
        var properties = { albumId: albumId, albumName: albumName }
        var incubator = pageLayout.addPageToNextColumn(
            pageLayout.primaryPage, albumPageComponent, properties)
        if (incubator) {
            albumIncubator = incubator
            incubator.onStatusChanged = function(status) {
                if (status === Component.Ready) {
                    albumPageInstance = incubator.object
                    albumBirthWide = wideMode
                    // Two-column mount: the APL back action hides across
                    // columns and the nav bar is hidden, so assign the
                    // close action directly on the instance (function
                    // references do not survive creation-properties
                    // injection).
                    if (wideMode) {
                        incubator.object.wideMount = true
                        incubator.object.closeCallback = closeAlbum
                    }
                    incubator.object.Component.destruction.connect(function() {
                        albumPageInstance = null
                        albumBirthWide = false
                        scheduleCol1Restore()
                    })
                    albumIncubator = null
                } else if (status === Component.Error) {
                    albumIncubator = null
                }
            }
        }
    }

    function closeAlbum() {
        pageLayout.removePages(albumPageInstance)
    }

    function openPlaylist(playlistId, playlistName) {
        console.log('navBar: openPlaylist wideMode=' + wideMode)
        // Lands directly on top of the Library page in both layouts:
        // single-column pushes onto the stack above it, and in
        // two-column mode Library is the rightmost column so the
        // same call stacks there too. The APL back action applies -
        // no close action and no instance/incubator tracking.
        pageLayout.addPageToNextColumn(
            libraryPageInstance, playlistDetailPageComponent,
            { playlistId: playlistId, playlistName: playlistName })
    }

    function openPlayer() {
        console.log('navBar: openPlayer wideMode=' + wideMode)
        // Guard against stacking a second player page.
        if (playerPageInstance === null) {
            var properties = {}
            var incubator = pageLayout.addPageToNextColumn(
                pageLayout.primaryPage, playerPageComponent, properties)
            if (incubator) {
                playerIncubator = incubator
                incubator.onStatusChanged = function(status) {
                    if (status === Component.Ready) {
                        playerPageInstance = incubator.object
                        playerBirthWide = wideMode
                        if (wideMode) {
                            incubator.object.wideMount = true
                            incubator.object.closeCallback = closePlayer
                        }
                        incubator.object.Component.destruction.connect(function() {
                            playerPageInstance = null
                            playerBirthWide = false
                            scheduleCol1Restore()
                        })
                        playerIncubator = null
                    } else if (status === Component.Error) {
                        playerIncubator = null
                    }
                }
            }
        }
    }

    function closePlayer() {
        pageLayout.removePages(playerPageInstance)
    }

    // Single-to-two-column migration: pages born while single-column
    // live in the primary page's column-0 subtree and would strand
    // column 1 empty after the layout grows. Remove them surgically
    // (the primary page is never touched) and reopen the
    // highest-priority one via migrationTimer.
    function migrateToTwoColumns() {
        console.log('navBar: migrateToTwoColumns'
            + ' libraryInstance=' + (libraryPageInstance !== null)
            + ' libraryBirthWide=' + libraryBirthWide
            + ' albumInstance=' + (albumPageInstance !== null)
            + ' albumBirthWide=' + albumBirthWide
            + ' playerInstance=' + (playerPageInstance !== null)
            + ' playerBirthWide=' + playerBirthWide)
        var hasSingleLibrary = libraryPageInstance !== null && !libraryBirthWide
        var hasSingleAlbum = albumPageInstance !== null && !albumBirthWide
        var hasSinglePlayer = playerPageInstance !== null && !playerBirthWide
        if (!hasSingleLibrary && !hasSingleAlbum && !hasSinglePlayer) {
            // Nothing single-born: wide-born pages are APL's business;
            // an empty column 1 falls through to maybeMountLibrary
            // as today.
            return
        }
        // Capture album data BEFORE removal.
        if (hasSingleAlbum) {
            pendingAlbumId = albumPageInstance.albumId
            pendingAlbumName = albumPageInstance.albumName
        }
        // Surgical removal: each call drops that page and its
        // subtree. Wide-born column-1 pages are a different subtree
        // and survive.
        if (hasSingleLibrary) {
            pageLayout.removePages(libraryPageInstance)
        }
        if (hasSingleAlbum) {
            pageLayout.removePages(albumPageInstance)
        }
        if (hasSinglePlayer) {
            pageLayout.removePages(playerPageInstance)
        }
        // Reopen by priority: player first (locked decision), else
        // album, else library.
        if (hasSinglePlayer) {
            pendingReopen = 'player'
        } else if (hasSingleAlbum) {
            pendingReopen = 'album'
        } else {
            pendingReopen = 'library'
        }
        migrationTimer.restart()
    }

    function maybeMountLibrary() {
        console.log('navBar: maybeMountLibrary wideMode=' + wideMode
            + ' libraryInstance=' + (libraryPageInstance !== null)
            + ' libraryIncubator=' + (libraryIncubator !== null)
            + ' albumInstance=' + (albumPageInstance !== null)
            + ' albumIncubator=' + (albumIncubator !== null)
            + ' playerInstance=' + (playerPageInstance !== null)
            + ' playerIncubator=' + (playerIncubator !== null))
        // Column-1 restore: fire only when column 1 is genuinely empty.
        // The primaryPage check covers the startup window in which
        // wideModeAllowed flips before primaryPageSource is assigned.
        // parent === null means APL has not finished registering the page.
        if (wideMode
                && pageLayout.primaryPage !== null
                && pageLayout.primaryPage.parent !== null
                && libraryPageInstance === null
                && libraryIncubator === null
                && albumPageInstance === null
                && albumIncubator === null
                && playerPageInstance === null) {
            mountLibraryDefault()
        }
    }

    function scheduleCol1Restore() {
        // The deferral prevents an evicted page's destruction from
        // remounting over the page that replaced it.
        col1RestoreTimer.restart()
    }

    // Home and Library. Future buttons Settings + About go here.
    Row {
        anchors.fill: parent

        Item {
            width: parent.width / 2
            height: parent.height

            Label {
                anchors.centerIn: parent
                text: i18n.tr('Home')
            }

            MouseArea {
                anchors.fill: parent
                onClicked: homeTapped()
            }
        }

        Item {
            width: parent.width / 2
            height: parent.height

            Label {
                anchors.centerIn: parent
                text: i18n.tr('Library')
            }

            MouseArea {
                anchors.fill: parent
                onClicked: libraryTapped()
            }
        }
    }

    Timer {
        id: col1RestoreTimer
        interval: 300
        repeat: false
        onTriggered: maybeMountLibrary()
    }

    // Deferred reopen for migrateToTwoColumns. The 300ms deferral
    // lets the destruction handlers of removed pages settle BEFORE
    // the reopen, so the instance guards see a clean state (same
    // discipline as scheduleCol1Restore).
    Timer {
        id: migrationTimer
        interval: 300
        repeat: false
        onTriggered: {
            console.log('navBar: migrationTimer reopen=' + pendingReopen)
            if (pendingReopen === 'player') {
                openPlayer()
            } else if (pendingReopen === 'album') {
                openAlbum(pendingAlbumId, pendingAlbumName)
            } else if (pendingReopen === 'library') {
                mountLibraryDefault()
            }
            pendingReopen = ''
        }
    }

    Connections {
        target: pageLayout
        onPrimaryPageChanged: maybeMountLibrary()
    }

    // Mounts the Library into column 1 when phone-landscape rotation
    // engages 2-column mode. Single-born pages are migrated FIRST so
    // they reopen as column-1 citizens; maybeMountLibrary remains the
    // unchanged fallthrough for the all-empty case.
    onWideModeChanged: {
        if (wideMode) {
            migrateToTwoColumns()
        }
        maybeMountLibrary()
    }
}
