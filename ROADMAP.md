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

- **Desktop packaging: AppImage is THE desktop release format** —
  first release and onward, not just a tester stopgap. Flatpak/
  Flathub = possible future addition, revisit when the time comes.
  Container/docker route rejected: container audio ignores host
  volume (own Pulse stream — his maxed-knob annoyance). Effort:
  AppImage = a session or two (copy prebuilt files from the clickable
  image into an AppDir + launcher + appimagetool — the image he
  trusts daily); Flatpak = days BECAUSE Flathub has no Lomiri
  Components runtime → flatpak-builder rebuilds the toolkit from
  source. One-liner: AppImage packages artifacts, Flatpak rebuilds
  the stack. The AppDir work doubles as the future Flatpak
  manifest's module list; re-check Flathub runtime availability
  whenever Flatpak is picked up. UT clicks need no work (already
  one-file installers).

- **Bitcoin donation link** — pending verification that UT opens
  `bitcoin:` wallet URIs from apps; owner unsure, revisit later.

- **About page version on the phone** — the version string renders on
  desktop but stays empty on phone installs. Two mechanisms attempted
  and parked on 2026-09-24 (bridge walk-up, QML XMLHttpRequest) — both
  work on desktop, neither on device. Very minor; needs on-device
  debugging (XHR status log) when anyone picks it up.

- **Login crash guard** — first-login after entering credentials can
  crash (seen once in clickable desktop, 2026-09-24; not reproducible
  on demand since). Credentials ARE stored before the crash, so a
  restart lands logged-in. Suspected uncaught exception in the
  login→error-page transition. Action when picked up: capture a log
  first (owner will hand one over when it recurs), then wrap the
  login/auth flow + page transition in a guarded try/catch that
  logs the exception instead of dying.

## Notes

- The settings menu itself (avatar dropdown, Settings page, About page)
  is the current active feature — not on this list.
- Engine `engine:` log breadcrumbs stay until store release (owner
  decision, separate from this roadmap).