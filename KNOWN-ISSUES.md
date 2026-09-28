# Known Issues - Power Ampache

State as of 2026-09-28.

## Confirmed behavior gaps

1. **Seek works only for MP3 streams.** FLAC and M4A do not seek (the bar
   jumps, audio does not). Suspected server-side cause, either container
   index / byte-range support or on-the-fly transcoding producing a live,
   non-seekable stream, still unverified. Confirm with `curl -sI`
   comparing `Accept-Ranges` and `Content-Length` between an mp3 and a
   flac or m4a stream URL. If confirmed, the fix belongs in Ampache's
   streaming or transcode config, not in QML.

2. **Repeat mode changes mid-queue apply from the next `playFrom()`.**
   The playlist shape is fixed at commit (repeat `off` commits the tail
   only; `all` and `one` commit the full rotation), while the
   playbackMode binding is live. Documented limitation.

3. **Repeat `one` replays the same stream URL each loop.** If the server
   counts plays per stream fetch, listen stats may inflate by one per
   loop. Known design edge (see the engine comment); needs review
   before a store release.

4. **No user-facing playback errors yet.** Stream failures are logged
   only (`engine: stream error code=...`); the UI shows nothing. Error
   surfacing is future work.

## Cosmetic and minor

5. **`playerIndex=NaN` in warm-up log lines.** The extended
   `hubPlaylist.currentIndex` breadcrumb computes modulo zero while the
   queue is empty during warm-up. Log-only, no behavior.

6. **Optimistic pause icon on a swallowed play.** `togglePlayPause`
   sets `playing = true` immediately; if media-hub swallows the
   `play()`, the icon shows pause for up to a second until the truth
   sampler corrects it.

7. **`next()` and `prev()` branch on `audioEngine.playbackState`**,
   not on the `engine.playing` mirror. If the state property is
   poisoned at that exact moment, a manual skip may re-call `play()`.
   Harmless, but inconsistent with the playing-truth model.

8. **App version invisible on the About page (phone only).** Desktop
   renders the version string; phone installs show the row empty. The
   manifest is installed at the click root (CMake install verified),
   but both read attempts failed on device: the bridge `__file__`
   walk-up and a QML XMLHttpRequest. Root cause unknown, parked as
   very minor. Next diagnostic if anyone picks it up: log the XHR
   status value on the phone.

## Recently fixed

- **First-login crash on desktop** (app dies right after entering
  credentials, wide window or tiled WM). Native SIGSEGV in the QML
  engine, root-caused as a race between the page-tree rebuild and the
  two-column layout switch at login. Fixed in 1.0.66: the wide-mode
  switch is deferred until the new page tree has settled.
- **Blank left column after returning from Settings.** Not observed
  since the page-instance guard rework on 2026-09-25. If it recurs,
  capture a log before restarting; the instance breadcrumbs tell the
  story.

## Testing status

Tested on phone and desktop through the current branch: login, library
browse, playback, shuffle, search, settings, player overlay.