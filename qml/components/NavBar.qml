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
    property var playerPageInstance
    property bool wideMode

    // Instance/incubator tracking - same pattern as Main.qml's
    // playerPageInstance: pages cannot be reused, only Components.
    property var libraryPageInstance: null
    property var albumPageInstance: null
    property var libraryIncubator: null
    property var albumIncubator: null

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
        libraryIncubator = incubator
        if (incubator) {
            incubator.onStatusChanged = function(status) {
                if (status === Component.Ready) {
                    libraryPageInstance = incubator.object
                    incubator.object.Component.destruction.connect(function() {
                        libraryPageInstance = null
                    })
                    libraryIncubator = null
                } else if (status === Component.Error) {
                    libraryIncubator = null
                }
            }
        }
    }

    function mountLibraryDefault() {
        // The 2-column desktop mount: Library lives in column 1.
        var incubator = pageLayout.addPageToNextColumn(
            pageLayout.primaryPage, libraryPageComponent)
        libraryIncubator = incubator
        if (incubator) {
            incubator.onStatusChanged = function(status) {
                if (status === Component.Ready) {
                    libraryPageInstance = incubator.object
                    incubator.object.Component.destruction.connect(function() {
                        libraryPageInstance = null
                    })
                    libraryIncubator = null
                } else if (status === Component.Error) {
                    libraryIncubator = null
                }
            }
        }
    }

    function openAlbum(albumId, albumName) {
        var incubator = pageLayout.addPageToNextColumn(
            pageLayout.primaryPage, albumPageComponent,
            { albumId: albumId, albumName: albumName })
        albumIncubator = incubator
        if (incubator) {
            incubator.onStatusChanged = function(status) {
                if (status === Component.Ready) {
                    albumPageInstance = incubator.object
                    incubator.object.Component.destruction.connect(function() {
                        albumPageInstance = null
                        scheduleCol1Restore()
                    })
                    albumIncubator = null
                } else if (status === Component.Error) {
                    albumIncubator = null
                }
            }
        }
    }

    function maybeMountLibrary() {
        // Column-1 restore: fire only when column 1 is genuinely empty.
        // The primaryPage check covers the startup window in which
        // wideModeAllowed flips before primaryPageSource is assigned.
        if (wideMode
                && pageLayout.primaryPage !== null
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

    Connections {
        target: pageLayout
        onPrimaryPageChanged: maybeMountLibrary()
    }

    // Mounts the Library into column 1 when phone-landscape rotation
    // engages 2-column mode.
    onWideModeChanged: maybeMountLibrary()
}
