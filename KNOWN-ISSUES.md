# Known Issues — PowerAmpache (UT)

State as of 2026-09-14. Player engine lineage: `bug/player-fix` @ 53e7ef4,
with `feat/seek` on top.

## Confirmed behavior gaps

1. **Seek works only for MP3 streams.** FLAC and M4A do not seek (the bar
   jumps, audio does not). Suspected server-side cause — container index /
   byte-range support, or on-the-fly transcoding producing a live,
   non-seekable stream — **unverified**. Confirm with `curl -sI` comparing
   `Accept-Ranges` / `Content-Length` between an mp3 and a flac/m4a stream
   URL. If confirmed, the fix belongs in Ampache's streaming/transcode
   config, not QML.

2. **Repeat mode changes mid-queue apply from the next `playFrom()`.**
   Playlist shape is fixed at commit (repeat `off` commits the tail only;
   `all`/`one` commit the full rotation), while the playbackMode binding is
   live. Documented limitation, not a bug per se.

3. **Repeat `one` replays the same stream URL each loop.** If the server
   counts plays per stream fetch, listen stats may inflate by one per loop.
   Known design edge (engine comment), needs review before any store
   release.

4. **No user-facing playback errors yet.** Stream failures are logged only
   (`engine: stream error code=...`); the UI shows nothing. Error surfacing
   is future work.

## Cosmetic / minor

5. **`playerIndex=NaN` in warm-up log lines.** The extended
   `hubPlaylist.currentIndex` breadcrumb computes modulo zero while the
   queue is empty during warm-up. Log-only, no behavior.

6. **Optimistic pause icon on a swallowed play.** `togglePlayPause` sets
   `playing = true` immediately; if media-hub swallows the `play()`, the
   icon shows pause for up to 1 s until the truth sampler corrects.

7. **`next()`/`prev()` branch on `audioEngine.playbackState`**, not the
   `engine.playing` mirror. If the state property is poisoned at that exact
   moment, a manual skip may re-call `play()` — harmless, but inconsistent
   with the playing-truth model.

8. **App version invisible on the About page (phone only).** Desktop
   renders the version string; phone installs show the row empty. The
   manifest IS installed at the click root (CMake install verified), but
   both read attempts failed on device: the bridge `__file__` walk-up
   (1.0.52) and the QML `Qt.resolvedUrl` XMLHttpRequest (1.0.53).
   Root cause unidentified — parked 2026-09-24 as very minor, not worth
   more time. Next diagnostic if ever picked up: log the XHR status
   value on the phone.

9. **First login fails after entering credentials ("server unreachable"),
   app may crash; restart works.** Seen once in clickable desktop
   (2026-09-24), not reproducible on demand since; credentials ARE
   stored before the failure, so a restart lands logged-in. Suspected
   uncaught exception in the login→error-page transition. Parked by
   owner decision pending a captured log; guard item on the ROADMAP.

10. **Blank left column (wide mode) after returning from Settings
    (2 occurrences, 2026-09-24).** First seen after repeated theme
    switches, then WITHOUT any theme change — just Settings → back.
    NOT theme-caused: a pre-existing navBar mount-state bug now
    surfacing under heavy Settings/wide-mode navigation. Failure
    signature (logged): navBar holds libraryInstance=true while the
    column renders blank — the cached mount reference goes stale
    (possibly an APL page-wrapper teardown, e.g. the "sourcePage must
    be added to the view" rejection logged at boot), so remount
    logic believes the library is mounted and skips. Recovery:
    restart. Recurring enough to warrant a real fix round: audit
    navBar's maybeMountLibrary/mountLibraryDefault path (does it
    verify the instance is actually IN the APL, or only check its
    own cache?) and re-mount on detected absence.

## Testing status

- Phone installs and testing are ongoing alongside desktop (phone
  tested since the v1.0.1 install on 09-12). Soak in progress:
  late-stop-echo handling (ignore + 400 ms re-arm window) and the
  EndOfMedia fallback are under continued testing.