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

import json
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

# Ids the server reports as having NO art (has_art=0 in the raw
# payload rows). The art URL is built unconditionally and serves a
# server-side placeholder image, so artUrl alone can never identify
# artless rows; this set is rebuilt from payload rows on every fetch.
# Session memory only: rows never re-fetched default to artful.
_ARTLESS_IDS = {'album': set(), 'artist': set(), 'playlist': set()}

# App-owned settings (settings.json beside the cache DB; the Room
# schema is read-only and LocalSettingsEntity has no column with
# matching semantics). None = not read yet; the dict is cached and
# mutated in place so setters stay coherent.
_appSettings = None


def _getAppSettings():
    "Read settings.json from the app data dir; a missing or corrupt file means empty settings."
    global _appSettings
    if _appSettings is None:
        settingsPath = os.path.join(os.path.dirname(getDbPath()), 'settings.json')
        try:
            with open(settingsPath, 'r') as settingsFile:
                _appSettings = json.load(settingsFile)
        except (OSError, ValueError):
            _appSettings = {}
    return _appSettings


def _useServerPlaceholder():
    "True when the user chose the server's own placeholder art over the app fallback."
    return bool(_getAppSettings().get('useServerPlaceholder'))


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


def _captureHasArt(rows, kind):
    "Record which payload rows the server says have no art. Ids are normalized to strings (server JSON ids are strings)."
    if not rows:
        return
    for row in rows:
        objectId = str(row.get('id') or '')
        if not objectId:
            continue
        rawHasArt = row.get('has_art')
        if rawHasArt is None:
            # Missing flag: default artful (do not punish rows the
            # server never labeled).
            hasArt = 1
        else:
            try:
                # JSON booleans: int(True)==1, int(False)==0. Never a
                # falsy default - False must stay False or the artless
                # fallback can never fire.
                hasArt = int(rawHasArt)
            except (TypeError, ValueError):
                # Unconvertable forms ('true'/'false' style strings)
                # resolve via explicit truthiness.
                hasArt = 1 if rawHasArt in (True, 'true', 'True', 1, '1') else 0
        if hasArt == 0:
            _ARTLESS_IDS[kind].add(objectId)
        else:
            _ARTLESS_IDS[kind].discard(objectId)


def _albumHasArt(albumId):
    return _useServerPlaceholder() or str(albumId) not in _ARTLESS_IDS['album']


def _artistHasArt(artistId):
    return _useServerPlaceholder() or str(artistId) not in _ARTLESS_IDS['artist']


def _playlistHasArt(playlistId):
    return _useServerPlaceholder() or str(playlistId) not in _ARTLESS_IDS['playlist']


def _streamingBitrate():
    "Stored streaming quality for stream URLs; None = omit the bitrate param (original quality)."
    try:
        dbPath = getDbPath()
        if not os.path.exists(dbPath):
            return None
        connection = sqlite3.connect(dbPath)
        try:
            row = connection.execute(
                'SELECT streamingQuality FROM LocalSettingsEntity LIMIT 1'
            ).fetchone()
            if row is None or row[0] is None:
                return None
            quality = int(row[0])
            # 0 was the pre-1.0.27 "lossless" marker; any non-positive
            # stored value means "omit the bitrate param" (original
            # quality).
            return quality if quality > 0 else None
        finally:
            connection.close()
    except Exception:
        return None


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
        'hasArt': _albumHasArt(album.id),
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
        'hasArt': _albumHasArt(song.albumId),
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
        'hasArt': _artistHasArt(artist.id),
    }


def _albumList(fetcher):
    "Run a limit-bounded fetch; the library persists the response and reads back from the cache."
    try:
        client = getClient()
        albums = fetcher(client)
        # Stats responses carry the album rows; capture their has_art
        # flags before mapping.
        _captureHasArt((client.lastPayload or {}).get('album') or [], 'album')
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
                    'hasArt': _albumHasArt(row[0]),
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
        # Self-paginated in 500-row pages with short-page termination
        # (the searchPlaylists shape): a bare list call auto-paginates
        # and lastPayload keeps ONLY the last page, so has_art capture
        # would miss rows. The return value is discarded, the cache DB
        # is the source of truth.
        offset = 0
        while True:
            client.getPlaylists(offset=offset, limit=_SEARCH_PAGE_SIZE)
            pageRows = (client.lastPayload or {}).get('playlist') or []
            _captureHasArt(pageRows, 'playlist')
            if len(pageRows) < _SEARCH_PAGE_SIZE:
                break
            offset += _SEARCH_PAGE_SIZE
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
                    'hasArt': _playlistHasArt(row[0]),
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
        _captureHasArt(pageRows, 'album')
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
                    'hasArt': _albumHasArt(row[0]),
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
        _captureHasArt(pageRows, 'artist')
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
        # The include payload nests the artist's albums under the same
        # 'album' key; capture their has_art flags.
        _captureHasArt((client.lastPayload or {}).get('album') or [], 'album')
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
                    'hasArt': _albumHasArt(row[0]),
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
            _captureHasArt(pageRows, 'playlist')
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
                    'hasArt': _playlistHasArt(row[0]),
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
            _captureHasArt(pageRows, 'album')
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
                    'hasArt': _albumHasArt(row[0]),
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
                    'hasArt': _albumHasArt(row[4]),
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
            _captureHasArt(pageRows, 'artist')
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
                    'hasArt': _artistHasArt(row[0]),
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
    """Return a stream URL for the built-in player. The bitrate comes
    from the stored streaming quality (LocalSettingsEntity); None =
    original quality (the bitrate param is omitted). The stats argument
    passes through verbatim: real plays omit it (the library default
    records the play), the spike passes 0. The URL embeds the live
    session token - never log it, never persist it."""
    try:
        client = getClient()
        url = client.getStreamUrl(songId, bitrate=_streamingBitrate(), stats=stats)
        return {'ok': True, 'url': url}
    except Exception as exception:
        return _errorDict(exception)


def getStreamUrls(songIds, stats=None):
    """Return stream URLs for a list of song ids in one call, for the QML
    Playlist architecture: the media-hub opens tracks itself, so the whole
    queue is handed over as URLs at tap time. Pure URL building per id, no
    network. The bitrate comes from the stored streaming quality
    (LocalSettingsEntity); None = original quality. The stats argument
    passes through verbatim to every URL; real plays omit it. The URLs
    embed the live session token - never log them, never persist them."""
    try:
        client = getClient()
        urls = [client.getStreamUrl(songId, bitrate=_streamingBitrate(), stats=stats) for songId in songIds]
        return {'ok': True, 'urls': urls}
    except Exception as exception:
        return _errorDict(exception)


def getSongInfo(songId):
    "Song metadata for the Info tab: direct sqlite read from the cached SongEntity (local, no network), same pattern as getLyrics."
    try:
        dbPath = getDbPath()
        if not os.path.exists(dbPath):
            return {'ok': True, 'info': None}
        connection = sqlite3.connect(dbPath)
        try:
            cursor = connection.execute(
                'SELECT title, artistName, albumName, albumArtist, genre, year, '
                'trackNumber, disk, time, bitrate, rateHz, channels, size, '
                'playCount, rating, composer, comment, language, format, '
                'publisher, mbId, replayGainTrackGain '
                'FROM SongEntity WHERE mediaId = ?', (songId,)
            )
            row = cursor.fetchone()
            if row is None:
                return {'ok': True, 'info': None}
            keys = ['title', 'artistName', 'albumName', 'albumArtist', 'genre',
                    'year', 'trackNumber', 'disk', 'time', 'bitrate', 'rateHz',
                    'channels', 'size', 'playCount', 'rating', 'composer',
                    'comment', 'language', 'format', 'publisher', 'mbId',
                    'replayGainTrackGain']
            info = dict(zip(keys, row))
            # The genre column stores a JSON array of objects
            # ('[{"id":"9","name":"Metal"}]'); keep only the name of
            # each genre, comma-joined. A non-JSON value (bad tag)
            # falls through unchanged.
            try:
                genres = json.loads(info['genre'])
                info['genre'] = ', '.join(
                    genre['name'] for genre in genres
                    if isinstance(genre, dict) and 'name' in genre)
            except (ValueError, TypeError):
                pass
            return {'ok': True, 'info': info}
        finally:
            connection.close()
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


def getUserInfo():
    "Menu header: username + server address from the stored credentials (local read, no network)."
    try:
        dbPath = getDbPath()
        if not os.path.exists(dbPath):
            return {'ok': False, 'errorKind': 'credentials', 'message': 'no credentials stored'}
        connection = sqlite3.connect(dbPath)
        try:
            row = connection.execute(
                'SELECT username, serverUrl FROM CredentialsEntity LIMIT 1'
            ).fetchone()
            if row is None:
                return {'ok': False, 'errorKind': 'credentials', 'message': 'no credentials stored'}
            return {'ok': True, 'username': row[0], 'serverUrl': row[1]}
        finally:
            connection.close()
    except Exception as exception:
        return _errorDict(exception)


def getServerInfo():
    "About page: server address + API version + catalog counts from SessionEntity (local read, no network)."
    try:
        dbPath = getDbPath()
        if not os.path.exists(dbPath):
            return {'ok': False, 'errorKind': 'credentials', 'message': 'no session stored'}
        connection = sqlite3.connect(dbPath)
        try:
            row = connection.execute(
                'SELECT api, songs, albums, artists, playlists FROM SessionEntity LIMIT 1'
            ).fetchone()
            if row is None:
                return {'ok': False, 'errorKind': 'credentials', 'message': 'no session stored'}
            return {'ok': True, 'api': row[0], 'songs': row[1], 'albums': row[2],
                    'artists': row[3], 'playlists': row[4]}
        finally:
            connection.close()
    except Exception as exception:
        return _errorDict(exception)


def getAppInfo():
    "About page: app title + version from the installed manifest.json (click root, one level above src/)."
    try:
        manifestPath = os.path.join(
            os.path.dirname(os.path.abspath(__file__)), '..', 'manifest.json')
        with open(manifestPath, 'r') as manifestFile:
            manifest = json.load(manifestFile)
        return {'ok': True, 'title': manifest.get('title', ''),
                'version': manifest.get('version', '')}
    except Exception as exception:
        return _errorDict(exception)


def getStreamingQuality():
    "Current stored streaming quality, RAW: 0 = lossless (original quality). ORIGINAL QUALITY (0) is the default when nothing is stored — a fresh install must not force a transcode; the schema column default (320) is not consulted. Must NOT reuse _streamingBitrate - it maps the stored 0 to None for URL building, and this function must tell 'nothing stored' (0 default) apart from '0 stored' (also 0, same UI outcome) while never collapsing to 320."
    try:
        dbPath = getDbPath()
        if not os.path.exists(dbPath):
            return {'ok': True, 'quality': 0}
        connection = sqlite3.connect(dbPath)
        try:
            row = connection.execute(
                'SELECT streamingQuality FROM LocalSettingsEntity LIMIT 1'
            ).fetchone()
            if row is None or row[0] is None:
                return {'ok': True, 'quality': 0}
            return {'ok': True, 'quality': int(row[0])}
        finally:
            connection.close()
    except Exception as exception:
        return _errorDict(exception)


def setStreamingQuality(quality):
    "Persist the streaming quality in LocalSettingsEntity (app-owned table, library never writes it). 0 = lossless (bitrate param omitted)."
    try:
        dbPath = getDbPath()
        ensureDatabase(dbPath)
        connection = sqlite3.connect(dbPath)
        try:
            connection.execute(
                'INSERT OR REPLACE INTO LocalSettingsEntity '
                "(username, theme, enableRemoteLogging, hideDonationButton, smartDownloadEnabled, "
                'enableAutoUpdates, streamingQuality, isNormalizeVolumeEnabled, '
                'isMonoAudioEnabled, isGlobalShuffleEnabled, playlistSongsSorting, '
                'isOfflineModeEnabled, isDownloadsSdCard, sleepTimerMinutes, '
                "saveSongAfterPlayback, saveFavouriteSongAfterPlayback) "
                "VALUES ((SELECT username FROM CredentialsEntity LIMIT 1), '', 0, 0, 0, 0, ?, 0, 0, 0, 'ASC', 0, 0, 0, 0, 0)",
                (int(quality),)
            )
            connection.commit()
        finally:
            connection.close()
        return {'ok': True}
    except Exception as exception:
        return _errorDict(exception)


def getServerPlaceholderSetting():
    "Current 'Use server placeholder art' value; off (False) by default."
    return {'ok': True, 'enabled': _useServerPlaceholder()}


def setServerPlaceholderSetting(enabled):
    "Persist the 'Use server placeholder art' choice in settings.json (cached dict updated in place, so the change applies to every later dict build without restart)."
    try:
        _getAppSettings()['useServerPlaceholder'] = bool(enabled)
        settingsPath = os.path.join(os.path.dirname(getDbPath()), 'settings.json')
        with open(settingsPath, 'w') as settingsFile:
            json.dump(_getAppSettings(), settingsFile)
        return {'ok': True}
    except Exception as exception:
        return _errorDict(exception)


def getCacheStats():
    "Cache size panel: row counts + total song bytes from the cache tables (local read, no network)."
    try:
        dbPath = getDbPath()
        if not os.path.exists(dbPath):
            return {'ok': True, 'songs': 0, 'albums': 0, 'artists': 0,
                    'playlists': 0, 'totalSize': 0}
        connection = sqlite3.connect(dbPath)
        try:
            def _count(table):
                return connection.execute(
                    'SELECT COUNT(*) FROM ' + table).fetchone()[0]
            sizeRow = connection.execute(
                'SELECT COALESCE(SUM(size), 0) FROM SongEntity').fetchone()
            return {'ok': True,
                    'songs': _count('SongEntity'),
                    'albums': _count('AlbumEntity'),
                    'artists': _count('ArtistEntity'),
                    'playlists': _count('PlaylistEntity'),
                    'totalSize': sizeRow[0]}
        finally:
            connection.close()
    except Exception as exception:
        return _errorDict(exception)


def clearCache():
    "Clear cached music data. CredentialsEntity/SessionEntity/LocalSettingsEntity share this DB file and are PRESERVED — only data tables are deleted."
    try:
        dbPath = getDbPath()
        if os.path.exists(dbPath):
            connection = sqlite3.connect(dbPath)
            try:
                for table in ['SongEntity', 'AlbumEntity', 'ArtistEntity',
                              'PlaylistEntity', 'PlaylistSongEntity',
                              'GenreEntity', 'HistoryEntity',
                              'RecommendedArtistEntity',
                              'DownloadedSongEntity']:
                    connection.execute('DELETE FROM ' + table)
                connection.commit()
            finally:
                connection.close()
        return {'ok': True}
    except Exception as exception:
        return _errorDict(exception)


def logout():
    "Destroy the session (best-effort server goodbye, offline-safe) then delete the local session + credentials rows. The cache DB and LocalSettingsEntity survive. The thread-local client is discarded (goodbye() marks it terminated)."
    try:
        client = None
        try:
            client = getClient()
        except Exception:
            client = None
        if client is not None:
            try:
                client.goodbye()
            except Exception:
                pass
        dbPath = getDbPath()
        if os.path.exists(dbPath):
            connection = sqlite3.connect(dbPath)
            try:
                connection.execute('DELETE FROM SessionEntity')
                connection.execute('DELETE FROM CredentialsEntity')
                connection.commit()
            finally:
                connection.close()
        _threadLocal.client = None
        return {'ok': True}
    except Exception as exception:
        return _errorDict(exception)


def getArtistInfo(artistId):
    "Artist header: songCount + genre names + flag from the cached ArtistEntity row (local read, no network; the row is persisted by getArtistsPage/getArtistAlbums)."
    try:
        dbPath = getDbPath()
        if not os.path.exists(dbPath):
            return {'ok': True, 'songCount': 0, 'genres': [], 'flag': False,
                    'artUrl': '', 'hasArt': False}
        connection = sqlite3.connect(dbPath)
        try:
            row = connection.execute(
                'SELECT songCount, genre, flag, artUrl FROM ArtistEntity WHERE id = ?',
                (str(artistId),)
            ).fetchone()
            if row is None:
                return {'ok': True, 'songCount': 0, 'genres': [], 'flag': False,
                        'artUrl': '', 'hasArt': False}
            genres = []
            try:
                parsed = json.loads(row[1])
                genres = [entry['name'] for entry in parsed
                          if isinstance(entry, dict) and 'name' in entry]
            except (ValueError, TypeError):
                pass
            return {'ok': True, 'songCount': int(row[0]), 'genres': genres,
                    'flag': bool(row[2]), 'artUrl': row[3],
                    'hasArt': _artistHasArt(artistId)}
        finally:
            connection.close()
    except Exception as exception:
        return _errorDict(exception)


def flagArtist(artistId, flagged):
    "Like/unlike the artist: server flag + verified re-fetch (client.flag) which write-through refreshes the cached ArtistEntity. Returns the fresh flag."
    try:
        client = getClient()
        entity = client.flag('artist', artistId, bool(flagged))
        return {'ok': True, 'flag': bool(entity.flag)}
    except Exception as exception:
        return _errorDict(exception)


def getArtistSongs(artistId):
    "All songs of one artist for play-all: write-through fetch, read back from the cache ordered by searchTitle. Same dict shape as getAlbumSongs."
    try:
        client = getClient()
        songs = client.getArtistSongs(artistId)
        return {'ok': True, 'songs': [_songDict(song) for song in songs]}
    except Exception as exception:
        return _errorDict(exception)


def getAlbumInfo(albumId):
    "Album header: artist, year, total time (seconds), song count, genre + featured artist name lists, flag + art from the cached AlbumEntity row (local read, no network)."
    try:
        dbPath = getDbPath()
        if not os.path.exists(dbPath):
            return {'ok': True, 'artistName': '', 'year': 0, 'time': 0,
                    'songCount': 0, 'genres': [], 'artists': [],
                    'flag': False, 'artUrl': '', 'hasArt': False}
        connection = sqlite3.connect(dbPath)
        try:
            row = connection.execute(
                'SELECT artistName, year, time, songCount, genre, artists, '
                'flag, artUrl FROM AlbumEntity WHERE id = ?',
                (str(albumId),)
            ).fetchone()
            if row is None:
                return {'ok': True, 'artistName': '', 'year': 0, 'time': 0,
                        'songCount': 0, 'genres': [], 'artists': [],
                        'flag': False, 'artUrl': '', 'hasArt': False}
            def _names(fragment):
                try:
                    parsed = json.loads(fragment)
                    return [entry['name'] for entry in parsed
                            if isinstance(entry, dict) and 'name' in entry]
                except (ValueError, TypeError):
                    return []
            return {'ok': True, 'artistName': row[0], 'year': int(row[1]),
                    'time': int(row[2]), 'songCount': int(row[3]),
                    'genres': _names(row[4]), 'artists': _names(row[5]),
                    'flag': bool(row[6]), 'artUrl': row[7],
                    'hasArt': _albumHasArt(albumId)}
        finally:
            connection.close()
    except Exception as exception:
        return _errorDict(exception)


def flagAlbum(albumId, flagged):
    "Like/unlike the album: server flag + verified re-fetch (client.flag) which write-through refreshes the cached AlbumEntity. Returns the fresh flag."
    try:
        client = getClient()
        entity = client.flag('album', albumId, bool(flagged))
        return {'ok': True, 'flag': bool(entity.flag)}
    except Exception as exception:
        return _errorDict(exception)


def getPlaylistInfo(playlistId):
    "Playlist header: song count + flag + art from the cached PlaylistEntity row (local read, no network). items is nullable - None means 0."
    try:
        dbPath = getDbPath()
        if not os.path.exists(dbPath):
            return {'ok': True, 'songCount': 0, 'flag': False,
                    'artUrl': '', 'hasArt': False}
        connection = sqlite3.connect(dbPath)
        try:
            row = connection.execute(
                'SELECT items, flag, artUrl FROM PlaylistEntity WHERE id = ?',
                (str(playlistId),)
            ).fetchone()
            if row is None:
                return {'ok': True, 'songCount': 0, 'flag': False,
                        'artUrl': '', 'hasArt': False}
            return {'ok': True, 'songCount': int(row[0] or 0),
                    'flag': bool(row[1]), 'artUrl': row[2],
                    'hasArt': _playlistHasArt(playlistId)}
        finally:
            connection.close()
    except Exception as exception:
        return _errorDict(exception)


def flagPlaylist(playlistId, flagged):
    "Like/unlike the playlist: server flag + verified re-fetch (client.flag) which write-through refreshes the cached PlaylistEntity. Returns the fresh flag."
    try:
        client = getClient()
        entity = client.flag('playlist', playlistId, bool(flagged))
        return {'ok': True, 'flag': bool(entity.flag)}
    except Exception as exception:
        return _errorDict(exception)
