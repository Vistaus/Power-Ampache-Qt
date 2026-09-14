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

## Testing status

- **Desktop-tested only** as of this writing. Phone install pending
  (version bump per install round). Soak in progress: late-stop-echo
  handling (ignore + 400 ms re-arm window) and the EndOfMedia fallback
  are under continued testing.