# Power Ampache

A music client for [Ampache](https://ampache.org/) servers, built for
Ubuntu Touch phones and Linux desktops.

Connect to your own Ampache server and stream your library over the
internet or your LAN. Your music stays on your server, under your
control. Nothing is locked in and there is no third party service in
the middle.

## Coming soon

- Star ratings for songs, albums and playlists
- Playlist creation and editing
- Per-song context menu
- Pull-to-refresh on Home and Library

Planned: downloads for offline listening.

## Features

- Library browsing: playlists, albums, songs and artists, with cover
  art pulled straight from your server
- Streaming playback with queue, shuffle, repeat modes, seek and
  in-player lyrics
- Search across the whole library
- Local cache: browsing fills it as you go, so pages open fast on
  slow connections and re-open offline
- Adaptive two-column layout on wide screens (rotate your phone to
  see it), mini player bar, pull-up player overlay on phones
- Light and dark themes
- Tested against Ampache 7.9.x (API 6) and 8.x (API 8) servers

## Install

On Ubuntu Touch, get the app from the OpenStore (first release is
being prepared; the link lands here the day it ships).

On Linux desktop, grab the AppImage (released alongside the first
version).

## Development

The app is Qt/QML on the front end and Python (PyOtherSide) on the
back end, using the
[ampachedata](https://github.com/icefields/Ampache-Data-Library)
library as its data layer (vendored in `src/ampachedata`). The client
library talks to the Ampache JSON API and keeps a local SQLite cache.

Build from source with
[Clickable](https://clickable-ut.dev):

```
clickable build
clickable install-phone
```

## Links

- Telegram announcements: https://t.me/PowerAmpache
- Telegram chat: https://t.me/PowerAmpache2
- Matrix: https://matrix.to/#/%23power-ampache:matrix.org
- Mastodon: https://floss.social/@powerampache
- Source: https://github.com/icefields/Power-Ampache-Qt

If you like the app, you can support it:

- Patreon: https://www.patreon.com/Icefields
- Buy Me a Coffee: https://buymeacoffee.com/powerampache
- PayPal: https://paypal.me/powerampache

## License

Copyright (C) 2026 icefields

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License version 3, as
published by the Free Software Foundation.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranties of
MERCHANTABILITY, SATISFACTORY QUALITY, or FITNESS FOR A PARTICULAR
PURPOSE. See the GNU General Public License for more details.