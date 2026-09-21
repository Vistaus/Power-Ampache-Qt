# SPDX-FileCopyrightText: 2026 icefields
# SPDX-License-Identifier: GPL-3.0-only
"""PyOtherSide bridge between QML and the ampachedata library.

QML calls module-level functions via python.call('bridge.functionName', ...).
No exception ever escapes to QML: every function returns a dict, a result
on success or {ok: False, errorKind, message} on failure, with errorKind
one of "credentials", "offline" or "unknown".

The library owns authentication (lazy handshake, transparent re-auth), so
this module adds no retry loops or session state of its own, and it never
logs passwords or stream URLs.
"""

import os
import socket
import sqlite3
import threading
import urllib.error

import ampachedata
from ampachedata import InvalidHandshakeError

_APP_DIR_NAME = 'powerampache.icefields'
_DB_FILE_NAME = 'musicdb.db'
_DEFAULT_LIMIT = 10
_SEARCH_PAGE_SIZE = 500

_threadLocal = threading.local()


def getDbPath():
    "Return the cache database path inside the XDG data dir."
    dataHome = os.environ.get('XDG_DATA_HOME')
    if not dataHome:
        dataHome = os.path.join(os.path.expanduser('~'), '.local', 'share')
    return os.path.join(dataHome, _APP_DIR_NAME, _DB_FILE_NAME)


def ensureDatabase(dbPath):
    "Create the cache database on first run; createDatabase refuses existing files."
    if os.path.exists(dbPath):
        return
    parentDir = os.path.dirname(dbPath)
    if parentDir:
        os.makedirs(parentDir, exist_ok=True)
    ampachedata.createDatabase(dbPath)


def getClient():
    "Return this thread's lazily created client; a client is never shared across threads (sqlite check_same_thread)."
    client = getattr(_threadLocal, 'client', None)
    if client is None:
        dbPath = getDbPath()
        ensureDatabase(dbPath)
        client = ampachedata.AmpacheClient(dbPath)
        _threadLocal.client = client
    return client


def _errorDict(exception):
    "Classify an exception at the QML boundary."
    if isinstance(exception, InvalidHandshakeError):
        errorKind = 'credentials'
    elif isinstance(exception, (urllib.error.URLError, socket.error)):
        errorKind = 'offline'
    else:
        errorKind = 'unknown'
    return {'ok': False, 'errorKind': errorKind, 'message': str(exception)}


def init():
    "One-time startup hook for QML: make sure the cache database exists before any other bridge call."
    try:
        ensureDatabase(getDbPath())
        return {'ok': True}
    except Exception as exception:
        return _errorDict(exception)


def hasCredentials():
    "Report whether credentials are stored; direct sqlite SELECT because the CredentialsEntity repository is library-internal."
    try:
        dbPath = getDbPath()
        if not os.path.exists(dbPath):
            return {'ok': True, 'hasCredentials': False}
        connection = sqlite3.connect(dbPath)
        try:
            cursor = connection.execute('SELECT COUNT(*) FROM CredentialsEntity')
            row = cursor.fetchone()
            return {'ok': True, 'hasCredentials': row[0] > 0}
        finally:
            connection.close()
    except Exception as exception:
        return _errorDict(exception)


def storeCredentials(serverUrl, username, password):
    "Store credentials; the library hashes the password in memory and it is never logged."
    try:
        dbPath = getDbPath()
        ensureDatabase(dbPath)
        # Library signature is (dbPath, username, serverUrl,
        # cleartextPassword) - dbPath first, serverUrl third, unlike
        # this function's parameter order. The password is never logged.
        ampachedata.storeCredentialsFromPassword(dbPath, username, serverUrl, password)
        return {'ok': True}
    except Exception as exception:
        return _errorDict(exception)


def authenticate():
    "Validate stored credentials with a real authenticated call; client.ping() is auth-blind and would validate nothing."
    try:
        client = getClient()
        client.getArtists(limit=1)
        return {'ok': True}
    except Exception as exception:
        return _errorDict(exception)


def _albumDict(album):
    "Map an Album domain object to a plain dict for QML."
    return {
        'id': album.id,
        'name': album.name,
        'artistName': album.artistName,
        'artUrl': album.artUrl,
        'year': album.year,
    }


def _songDict(song):
    "Map a Song domain object to a plain dict for QML."
    return {
        'id': song.id,
        'title': song.title,
        'trackNumber': song.trackNumber,
        'artistName': song.artistName,
        'albumId': song.albumId,
        'albumName': song.albumName,
        'time': song.time,
        'imageUrl': song.imageUrl,
    }


def _artistDict(artist):
    "Map an Artist domain object to a plain dict for QML."
    return {
        'id': artist.id,
        'name': artist.name,
        'albumCount': artist.albumCount,
        'songCount': artist.songCount,
        'artUrl': artist.artUrl,
        'flag': artist.flag,
    }


def _albumList(fetcher):
    "Run a limit-bounded fetch; the library persists the response and reads back from the cache."
    try:
        client = getClient()
        albums = fetcher(client)
        return {'ok': True, 'albums': [_albumDict(album) for album in albums]}
    except Exception as exception:
        return _errorDict(exception)


def getRecentAlbums(limit=_DEFAULT_LIMIT):
    "Home row 1: recently played."
    return _albumList(lambda client: client.getRecentAlbums(limit=limit))


def getFavouriteAlbums():
    "Home row 2: favourites. Ampache has no favourites API; the flag column is the mechanism, so this reads the cache directly."
    try:
        dbPath = getDbPath()
        if not os.path.exists(dbPath):
            return {'ok': True, 'albums': []}
        connection = sqlite3.connect(dbPath)
        try:
            cursor = connection.execute(
                'SELECT id, name, artistName, artUrl, year FROM AlbumEntity WHERE flag = 1'
            )
            albums = [
                {
                    'id': row[0],
                    'name': row[1],
                    'artistName': row[2],
                    'artUrl': row[3],
                    'year': row[4],
                }
                for row in cursor.fetchall()
            ]
            return {'ok': True, 'albums': albums}
        finally:
            connection.close()
    except Exception as exception:
        return _errorDict(exception)


def getFrequentAlbums(limit=_DEFAULT_LIMIT):
    "Home row 3: frequently played."
    return _albumList(lambda client: client.getFrequentAlbums(limit=limit))


def getHighestAlbums(limit=_DEFAULT_LIMIT):
    "Home row 4: highest rated."
    return _albumList(lambda client: client.getHighestAlbums(limit=limit))


def getNewestAlbums(limit=_DEFAULT_LIMIT):
    "Home row 5: newly added."
    return _albumList(lambda client: client.getNewestAlbums(limit=limit))


def getRandomAlbums(limit=_DEFAULT_LIMIT):
    "Home row 6: random."
    return _albumList(lambda client: client.getRandomAlbums(limit=limit))


def getPlaylists():
    "Library Playlists section: fetch from server, read back from cache (getFavouriteAlbums pattern)."
    try:
        dbPath = getDbPath()
        if not os.path.exists(dbPath):
            return {'ok': True, 'playlists': []}
        client = getClient()
        # The library auto-paginates and persists every response; the
        # return value is discarded, the cache DB is the source of truth.
        client.getPlaylists()
        connection = sqlite3.connect(dbPath)
        try:
            # Order: highest rated, flagged, owned by the logged-in user, smart playlists last, then insertion order.
            cursor = connection.execute(
                'SELECT id, name, owner, items, type, artUrl FROM PlaylistEntity '
                'ORDER BY preciseRating DESC, rating DESC, flag DESC, '
                'CASE WHEN owner = (SELECT username FROM CredentialsEntity LIMIT 1) THEN 0 ELSE 1 END, '
                "CASE WHEN id LIKE 'smart\\_%' ESCAPE '\\' THEN 1 ELSE 0 END, "
                'rowid ASC'
            )
            playlists = [
                {
                    'id': row[0],
                    'name': row[1],
                    'owner': row[2],
                    'items': row[3],
                    'type': row[4],
                    'artUrl': row[5],
                }
                for row in cursor.fetchall()
            ]
            return {'ok': True, 'playlists': playlists}
        finally:
            connection.close()
    except Exception as exception:
        return _errorDict(exception)


def getAlbumsPage(offset, limit=100):
    "Library Albums grid: fetch one chunk to grow the cache, then read back every cached album sorted by name; fetched/complete come from the true server page in client.lastPayload (the getAlbums return value is the full cache read-back, not the page) - fetched drives the next offset, complete drives Load-more visibility."
    try:
        client = getClient()
        # The return value is the full cache read-back, not the server
        # page; the true page size comes from lastPayload.
        client.getAlbums(offset=offset, limit=limit)
        pageRows = (client.lastPayload or {}).get('album') or []
        connection = sqlite3.connect(getDbPath())
        try:
            cursor = connection.execute(
                'SELECT id, name, artistName, artUrl, year FROM AlbumEntity '
                'ORDER BY name COLLATE NOCASE ASC'
            )
            albums = [
                {
                    'id': row[0],
                    'name': row[1],
                    'artistName': row[2],
                    'artUrl': row[3],
                    'year': row[4],
                }
                for row in cursor.fetchall()
            ]
            return {'ok': True, 'albums': albums, 'fetched': len(pageRows), 'complete': len(pageRows) < limit}
        finally:
            connection.close()
    except Exception as exception:
        return _errorDict(exception)


def getArtistsPage(offset, limit=100):
    "Library Artists grid, album artists only: fetch one chunk (albumArtist=1) to grow the cache, then return the full cache (the getArtists return value, ordered by searchName) filtered to albumCount > 0 - albumCount is the server-reported total, so this also hides song-artists persisted by older non-filtered sessions. fetched/complete come from the true server page in client.lastPayload, same pattern as getAlbumsPage."
    try:
        client = getClient()
        artists = client.getArtists(albumArtist=1, offset=offset, limit=limit)
        # The return value is the full cache read-back, not the server
        # page; the true page size comes from lastPayload.
        pageRows = (client.lastPayload or {}).get('artist') or []
        albumArtists = [artist for artist in artists if artist.albumCount > 0]
        return {
            'ok': True,
            'artists': [_artistDict(artist) for artist in albumArtists],
            'fetched': len(pageRows),
            'complete': len(pageRows) < limit,
        }
    except Exception as exception:
        return _errorDict(exception)


def getRecentSongs(limit=50):
    "Library Songs section: recently played, capped, never a full sync."
    try:
        client = getClient()
        songs = client.getRecentSongs(limit=limit)
        return {'ok': True, 'songs': [_songDict(song) for song in songs]}
    except Exception as exception:
        return _errorDict(exception)


def getAlbumSongs(albumId):
    "Album drill-down: the album's tracks in the order the response gives, never re-sorted."
    try:
        client = getClient()
        songs = client.getAlbumSongs(albumId)
        return {'ok': True, 'songs': [_songDict(song) for song in songs]}
    except Exception as exception:
        return _errorDict(exception)


def getArtistAlbums(artistId):
    "Artist drill-down: fetch the artist's albums (include=albums, persisted), read back from cache, newest first."
    try:
        dbPath = getDbPath()
        if not os.path.exists(dbPath):
            return {'ok': True, 'albums': []}
        client = getClient()
        # include='albums' persists the artist's albums; the return
        # value is discarded, the cache DB is the source of truth.
        client.getArtist(artistId, include='albums')
        connection = sqlite3.connect(dbPath)
        try:
            cursor = connection.execute(
                'SELECT id, name, artistName, artUrl, year FROM AlbumEntity '
                'WHERE artistId = ? '
                'ORDER BY year DESC, name COLLATE NOCASE ASC',
                (artistId,)
            )
            albums = [
                {
                    'id': row[0],
                    'name': row[1],
                    'artistName': row[2],
                    'artUrl': row[3],
                    'year': row[4],
                }
                for row in cursor.fetchall()
            ]
            return {'ok': True, 'albums': albums}
        finally:
            connection.close()
    except Exception as exception:
        return _errorDict(exception)


def getPlaylistSongs(playlistId):
    "Playlist drill-down: the playlist's tracks in position order, never re-sorted."
    try:
        client = getClient()
        songs = client.getSongsFromPlaylist(playlistId)
        return {'ok': True, 'songs': [_songDict(song) for song in songs]}
    except Exception as exception:
        return _errorDict(exception)


def searchPlaylists(query):
    "Library search, Playlists section: the server-side filter is a case-insensitive name substring match (PA2 semantics, verified live 09-16). An empty query returns an empty list with no network call. Self-paginated in 500-row pages with short-page termination: a bare list call would auto-paginate the whole library, lastPayload holds only the latest page, and total_count is unreliable. Write-through persists every fetched page, so searching grows the cache."
    if not query or not query.strip():
        return {'ok': True, 'playlists': []}
    try:
        client = getClient()
        matchedIds = set()
        offset = 0
        while True:
            client.getPlaylists(filter=query, offset=offset, limit=_SEARCH_PAGE_SIZE)
            pageRows = (client.lastPayload or {}).get('playlist') or []
            for pageRow in pageRows:
                matchedIds.add(str(pageRow.get('id')))
            if len(pageRows) < _SEARCH_PAGE_SIZE:
                break
            offset += _SEARCH_PAGE_SIZE
        if not matchedIds:
            return {'ok': True, 'playlists': []}
        connection = sqlite3.connect(getDbPath())
        try:
            # Same SELECT/ORDER BY as getPlaylists (rating/flag/owned/
            # smart ordering); the matched-id filter applies on top of
            # the cache read-back.
            cursor = connection.execute(
                'SELECT id, name, owner, items, type, artUrl FROM PlaylistEntity '
                'ORDER BY preciseRating DESC, rating DESC, flag DESC, '
                'CASE WHEN owner = (SELECT username FROM CredentialsEntity LIMIT 1) THEN 0 ELSE 1 END, '
                "CASE WHEN id LIKE 'smart\\_%' ESCAPE '\\' THEN 1 ELSE 0 END, "
                'rowid ASC'
            )
            playlists = [
                {
                    'id': row[0],
                    'name': row[1],
                    'owner': row[2],
                    'items': row[3],
                    'type': row[4],
                    'artUrl': row[5],
                }
                for row in cursor.fetchall()
                if str(row[0]) in matchedIds
            ]
            return {'ok': True, 'playlists': playlists}
        finally:
            connection.close()
    except Exception as exception:
        return _errorDict(exception)


def searchAlbums(query):
    "Library search, Albums section: the server-side filter is a case-insensitive title substring match (PA2 semantics, verified live 09-16). Same self-paginated shape as searchPlaylists: lastPayload holds only the latest page, total_count is unreliable, and write-through grows the cache with every fetched page."
    if not query or not query.strip():
        return {'ok': True, 'albums': []}
    try:
        client = getClient()
        matchedIds = set()
        offset = 0
        while True:
            client.getAlbums(filter=query, offset=offset, limit=_SEARCH_PAGE_SIZE)
            pageRows = (client.lastPayload or {}).get('album') or []
            for pageRow in pageRows:
                matchedIds.add(str(pageRow.get('id')))
            if len(pageRows) < _SEARCH_PAGE_SIZE:
                break
            offset += _SEARCH_PAGE_SIZE
        if not matchedIds:
            return {'ok': True, 'albums': []}
        connection = sqlite3.connect(getDbPath())
        try:
            # Same SELECT as getAlbumsPage; the matched-id filter
            # applies on top of the cache read-back.
            cursor = connection.execute(
                'SELECT id, name, artistName, artUrl, year FROM AlbumEntity '
                'ORDER BY name COLLATE NOCASE ASC'
            )
            albums = [
                {
                    'id': row[0],
                    'name': row[1],
                    'artistName': row[2],
                    'artUrl': row[3],
                    'year': row[4],
                }
                for row in cursor.fetchall()
                if str(row[0]) in matchedIds
            ]
            return {'ok': True, 'albums': albums}
        finally:
            connection.close()
    except Exception as exception:
        return _errorDict(exception)


def searchSongs(query):
    "Library search, Songs section: the server-side filter is a case-insensitive TITLE-ONLY substring match - artist names are not matched, accepted behavior, PA2-identical, verified live 09-16. Same self-paginated shape as searchPlaylists: lastPayload holds only the latest page, total_count is unreliable, and write-through grows the cache with every fetched page."
    if not query or not query.strip():
        return {'ok': True, 'songs': []}
    try:
        client = getClient()
        matchedIds = set()
        offset = 0
        while True:
            client.getSongs(filter=query, offset=offset, limit=_SEARCH_PAGE_SIZE)
            pageRows = (client.lastPayload or {}).get('song') or []
            for pageRow in pageRows:
                matchedIds.add(str(pageRow.get('id')))
            if len(pageRows) < _SEARCH_PAGE_SIZE:
                break
            offset += _SEARCH_PAGE_SIZE
        if not matchedIds:
            return {'ok': True, 'songs': []}
        connection = sqlite3.connect(getDbPath())
        try:
            cursor = connection.execute(
                'SELECT mediaId, title, trackNumber, artistName, albumId, albumName, time, imageUrl '
                'FROM SongEntity ORDER BY searchTitle COLLATE NOCASE, mediaId'
            )
            songs = [
                {
                    'id': row[0],
                    'title': row[1],
                    'trackNumber': row[2],
                    'artistName': row[3],
                    'albumId': row[4],
                    'albumName': row[5],
                    'time': row[6],
                    'imageUrl': row[7],
                }
                for row in cursor.fetchall()
                if str(row[0]) in matchedIds
            ]
            return {'ok': True, 'songs': songs}
        finally:
            connection.close()
    except Exception as exception:
        return _errorDict(exception)


def searchArtists(query):
    "Library search, Artists section: the server-side filter is a case-insensitive name substring match (PA2 semantics, verified live 09-16), album artists only (albumArtist=1, albumCount > 0 - album-artist discipline unchanged). Same self-paginated shape as searchPlaylists: lastPayload holds only the latest page, total_count is unreliable, and write-through grows the cache with every fetched page."
    if not query or not query.strip():
        return {'ok': True, 'artists': []}
    try:
        client = getClient()
        matchedIds = set()
        offset = 0
        while True:
            client.getArtists(albumArtist=1, filter=query, offset=offset, limit=_SEARCH_PAGE_SIZE)
            pageRows = (client.lastPayload or {}).get('artist') or []
            for pageRow in pageRows:
                matchedIds.add(str(pageRow.get('id')))
            if len(pageRows) < _SEARCH_PAGE_SIZE:
                break
            offset += _SEARCH_PAGE_SIZE
        if not matchedIds:
            return {'ok': True, 'artists': []}
        connection = sqlite3.connect(getDbPath())
        try:
            cursor = connection.execute(
                'SELECT id, name, albumCount, songCount, artUrl, flag FROM ArtistEntity '
                'ORDER BY searchName COLLATE NOCASE, id'
            )
            artists = [
                {
                    'id': row[0],
                    'name': row[1],
                    'albumCount': row[2],
                    'songCount': row[3],
                    'artUrl': row[4],
                    'flag': row[5],
                }
                for row in cursor.fetchall()
                if str(row[0]) in matchedIds and row[2] > 0
            ]
            return {'ok': True, 'artists': artists}
        finally:
            connection.close()
    except Exception as exception:
        return _errorDict(exception)


def getStreamUrl(songId, stats=None):
    """Return a stream URL for the built-in player. The stats argument
    passes through verbatim: real plays omit it (the library default
    records the play), the spike passes 0. The URL embeds the live
    session token - never log it, never persist it."""
    try:
        client = getClient()
        url = client.getStreamUrl(songId, stats=stats)
        return {'ok': True, 'url': url}
    except Exception as exception:
        return _errorDict(exception)


def getStreamUrls(songIds, stats=None):
    """Return stream URLs for a list of song ids in one call, for the QML
    Playlist architecture: the media-hub opens tracks itself, so the whole
    queue is handed over as URLs at tap time. Pure URL building per id, no
    network. The stats argument passes through verbatim to every URL; real
    plays omit it. The URLs embed the live session token - never log them,
    never persist them."""
    try:
        client = getClient()
        urls = [client.getStreamUrl(songId, stats=stats) for songId in songIds]
        return {'ok': True, 'urls': urls}
    except Exception as exception:
        return _errorDict(exception)


def getLyrics(songId):
    "Lyrics for the player page: the cached SongEntity.lyrics field via direct sqlite (local cache, no network), same pattern as getFavouriteAlbums."
    try:
        dbPath = getDbPath()
        if not os.path.exists(dbPath):
            return {'ok': True, 'lyrics': ''}
        connection = sqlite3.connect(dbPath)
        try:
            cursor = connection.execute(
                'SELECT lyrics FROM SongEntity WHERE mediaId = ?', (songId,)
            )
            row = cursor.fetchone()
            # A missing row or NULL lyrics both mean "no lyrics".
            lyrics = row[0] if row and row[0] else ''
            return {'ok': True, 'lyrics': lyrics}
        finally:
            connection.close()
    except Exception as exception:
        return _errorDict(exception)
