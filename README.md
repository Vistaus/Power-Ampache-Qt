# Power Ampache

A music client for [Ampache](https://ampache.org/) servers, built for
Ubuntu Touch phones and Linux desktops.

Connect to your own Ampache server and stream your library over the
internet or your LAN. Your music stays on your server, under your
control. Nothing is locked in and there is no third party service in
the middle.

### Ubuntu Touch Phone Screenshots
| - | - | - | - |
|---|---|---|---|
| <img width="1080" height="2400" alt="home-screen" src="https://github.com/user-attachments/assets/b86d16d3-6e0e-4880-a1aa-a80bdea8c447" /> | <img width="1080" height="2400" alt="player" src="https://github.com/user-attachments/assets/e0ebe6e6-3250-4f8b-86fb-9b8ea13c1acd" /> | <img width="1080" height="2400" alt="artist" src="https://github.com/user-attachments/assets/48ebea8c-2326-402b-b09f-9f23647d9f22" /> | <img width="1080" height="2400" alt="album" src="https://github.com/user-attachments/assets/7dab8cd7-ed8e-4391-88b6-dbfaff0832db" /> | 
| <img width="1080" height="2400" alt="artists" src="https://github.com/user-attachments/assets/1f6e429c-4d31-49c8-b6fd-a82b5ba5cb97" /> | <img width="1080" height="2400" alt="albums" src="https://github.com/user-attachments/assets/8fa1051d-2693-4b88-af5f-d032b3a29434" /> | <img width="1080" height="2400" alt="playlists" src="https://github.com/user-attachments/assets/90998a29-2216-4634-acb1-7679bd4fa790" /> | <img width="1080" height="2400" alt="album2" src="https://github.com/user-attachments/assets/f43925f8-a6fe-4153-82f8-2b968739c611" /> |


### Desktop Screenshots
| dark | light |
|---|---|
| <img width="1758" height="1409" alt="desktop-dark" src="https://github.com/user-attachments/assets/da25d297-9e20-4cc1-94f0-b5da2179f0d1" />  | <img width="1758" height="1408" alt="desktop-light" src="https://github.com/user-attachments/assets/0f8349f1-dddf-43d5-b705-b22ee8394132" />  |
## Coming soon

- Star ratings for songs, albums and playlists
- Playlist creation and editing
- Per-song context menu
- Pull-to-refresh on Home and Library

Planned: downloads for offline listening.

The app is under active development, with more features on the way.
If you run into any issues, please report them and they will be
addressed.

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

On Ubuntu Touch, download the app from the OpenStore. For the desktop version use Github Releases.




| Ubuntu Touch | Desktop |
|---|---|
| [![OpenStore](https://open-store.io/badges/en_US.svg)](https://open-store.io/app/powerampache.icefields/) | [Desktop Release](https://github.com/icefields/Power-Ampache-Qt/releases) |

On Linux desktop, grab the AppImage (released alongside the first
version).

## Development

The app uses the
[ampachedata](https://github.com/icefields/Ampache-Data-Library)
library (by the same developer) as its data layer (vendored in `src/ampachedata`).

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
