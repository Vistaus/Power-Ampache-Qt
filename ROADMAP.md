# ROADMAP

Deferred features, parked here so the main line stays focused. Order is
not a commitment; each item gets its own design conversation when
picked up.

## Later

- **Ratings and favourites.** Rate and flag actions in the UI (Song
  Info already displays the rating row; nothing can set it yet). The
  library ships `client.rate()` and `client.flag()`, so this is
  app-side wiring plus a cache-refresh verification round.

- **Downloads / offline cache.** Sonic's file:// download window
  pattern: first song streams instantly, the rest download ahead.
  Survives UT suspension for streams, the documented platform
  limitation the streaming architecture otherwise works around.
  Biggest lift in the backlog: getDownloadUrl tier, cache dir,
  eviction, UI.

- **Genre browse.** Needs the genre methods in ampachedata first
  (parked library tier), then a Library section or filter in the app.

- **Session save/restore.** Queue survives app close or OOM kill
  (Sonic's _saveSessionQueue/_restoreSessionQueue pattern). Nice to
  have; the engine already survives suspension for the current track.

- **Desktop packaging: AppImage is the desktop release format.** First
  release and onward, not just a tester stopgap. Flatpak on Flathub is
  a possible future addition, to revisit when the time comes. The
  container route was rejected because container audio ignores the
  host volume knob (each container gets its own Pulse stream).
  Effort: the AppImage is a session or two (copy prebuilt files from
  the clickable image into an AppDir, add a launcher, run
  appimagetool); Flatpak is days of work because Flathub ships no
  Lomiri Components runtime, so flatpak-builder would rebuild the
  toolkit from source. Short version: AppImage packages artifacts,
  Flatpak rebuilds the stack. The AppDir work doubles as the module
  list for a future Flatpak manifest; recheck Flathub runtime
  availability whenever Flatpak is picked up. UT clicks need no work.

- **UI Scale "System default" row.** The shipped scale section stores
  an explicit choice only; the initial state is unset (the launcher
  exports nothing and the session or compositor value applies, Qt
  default on plain machines). A "System default" row would follow the
  Theme section's "System" precedent: remove the uiScale key, export
  nothing, the dot sits there when unset. Parked 2026-09-25 with the
  feature working.

- **Bitcoin donation link.** Pending verification that UT opens
  `bitcoin:` wallet URIs from apps; revisit later.

- **About page version on the phone.** The version string renders on
  desktop but stays empty on phone installs. Two mechanisms attempted
  and parked on 2026-09-24 (bridge walk-up, QML XMLHttpRequest); both
  work on desktop, neither on device. Very minor; needs on-device
  debugging (XHR status log) when anyone picks it up.

## Notes

- Engine `engine:` log breadcrumbs stay until store release.