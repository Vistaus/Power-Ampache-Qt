# ROADMAP

Deferred features — parked here by decision on 2026-09-23 so the main
line stays focused. Order is not a commitment; each item gets its own
design conversation when picked up.

## Later

- **Ratings & favourites** — rate/flag actions in the UI (Song Info
  already displays the rating row; nothing can set it yet). The library
  ships `client.rate()` / `client.flag()` — this is app-side wiring
  plus an ampachedata cache-refresh verification round.

- **Downloads / offline cache** — Sonic's file:// download window
  pattern: first song streams instantly, rest download ahead. Survives
  UT suspension for streams (the documented platform limitation our
  streaming architecture otherwise works around). Biggest lift in the
  backlog: getDownloadUrl tier, cache dir, eviction, UI.

- **Genre browse** — needs the genre methods in ampachedata first
  (parked library tier), then a Library section or filter in the app.

- **Session save/restore** — queue survives app close/OOM-kill
  (Sonic's _saveSessionQueue/_restoreSessionQueue pattern). Nice-to-have;
  the engine already survives suspension for the current track.

- **Real user avatar** — the app menu currently has a placeholder circle
  (first letter of username): ampachedata's User domain entity and mapper
  are skeletons and no user API method exists yet. Landing `getUser` in
  the library (art URL from the server, UserEntity already has the `art`
  column) unlocks the real avatar image.

- **Desktop packaging for testers (AppImage)** — deferred until his
  own testing finishes. Container/docker route rejected: container
  audio ignores host volume (own Pulse stream). AppImage = the agreed
  eventual shape: bundle qmlscene + Lomiri Components + PyOtherSide +
  Python out of the clickable image into one portable file. UT clicks
  need no work (already one-file installers).

- **Bitcoin donation link** — pending verification that UT opens
  `bitcoin:` wallet URIs from apps; owner unsure, revisit later.

## Notes

- The settings menu itself (avatar dropdown, Settings page, About page)
  is the current active feature — not on this list.
- Engine `engine:` log breadcrumbs stay until store release (owner
  decision, separate from this roadmap).