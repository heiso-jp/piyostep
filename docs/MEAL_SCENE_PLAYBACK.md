# Meal scene playback — code-only integration handoff

The new user video is the only intended source. Earlier animation pilots remain
archived and are not imported by the app. The source ZIP could not be transferred
into this executor; the parent owns media slicing, pixel QA, and final assembly.
This commit contains playback/integration code and XCTest cases, not media assets.

## Changes

- `MealScenePlayback.swift` (PiyoCore): validated manifest adapter, independent
  seeded scene selector, timing clock. Every eligible scene completes before the
  next draw. The previous ID is excluded when another candidate exists. A single
  eligible candidate can repeat; an empty pool holds instead of force-unwrapping.
- `MealSceneView.swift` (app): ImageIO APNG or PNG-frame decoding, aspect-fit
  display, one active APNG source and one displayed UIImage. Wrong dimensions,
  frame count, paths, data or missing files fall back to the existing drawing.
- `MealRaceView.swift`: replaces only the companion's visual column when a valid
  matching-character catalog exists. Does not change timers, progress, race plan,
  rewards, speech, buddy/profile settings or the child's plate.
- `Resources/MealScenes/README.md`: exact media installation contract. No media
  or placeholder production manifest is installed in this patch.

The parent's compact manifest can be copied unchanged and named
`piyo-meal-scenes.json`. `finished.png` is also the reduced-motion static image.
The schema normalizer retains all original 100ms delays and checks declared total
durations. The 5 source gestures are all eligible for eating/resting/cheering.

## Playback lifecycle

- Repeated 0.5s engine updates only request an activity. They do not reset the
  current scene. Ordinary eating/resting/cheering changes apply at the next clip
  boundary; the most recent pending request wins.
- `.finished` is a priority terminal state: stop selection and show finished.png.
  A stale eating update cannot restart that player. Leaving the race screen
  invalidates the display link and releases the decoder.
- `isPlaying = false`, inactive/background, and leaving the window freeze the
  clock. Resume clears the old display timestamp; no background catch-up occurs.
  The existing race timer's wall-clock behavior remains unchanged.
- Reduce Motion or the existing UI-test reduceAnimations flag displays the
  supplied neutral still, with no advancing clock or recurring random draw.
  Turning it off resumes the held clip time. This also disables the old art's
  repeating motion when the fallback is displayed.
- Native display ticks are limited to 100ms after a UI stall so a stalled frame
  cannot fast-forward through multiple gestures. Normal 100ms source timing is
  unchanged; heavy UI stalls intentionally slow the animation rather than skip
  gestures. No audio is played or synthesized.
- The current scene is selected with a seed derived from the session seed using
  its own RandomSource. Race randomness is not consumed or modified.
- piyo media is never shown for another selected meal character. The pre-existing
  separation between settings.mealCharacterID and profile.buddyCharacterID is
  preserved. Both source profile/settings files remain unchanged.

## Validation status

Eight XCTest cases were added for the real PiyoCore implementation: 100 complete
clips/no immediate repeat/all five reachable, pending-state boundaries, pause and
reduced-motion clocks, terminal finish/stale update, empty/single pools, variable
frame delays/malformed resources, the compact manifest adapter, deterministic
seeds and duplicate-ID rejection.

`swift test` could not execute: `/bin/bash: swift: command not found` (exit 127).
There is no Swift/Xcode toolchain in this selected environment. These are authored
but UNRUN tests. Static diff checks are separate, not substitutes for compile or
runtime tests. No claim of local media pixel inspection is made.

Before shipping, run on the user's separately authorized Mac:

1. Install the parent's pixel-verified media and manifest as documented.
2. Run `swift test` in Packages/PiyoCore; build PiyoStep in Xcode 16+.
3. Run meal UI and confirm bundle resource lookup, actual APNG composition,
   original aspect ratio, all scene durations and no immediate repeat.
4. Toggle background/foreground, reduced motion, finish, close/reopen, and select
   each non-piyo buddy. Confirm no catch-up, stale restart, crash, or wrong buddy.
5. Remove/corrupt a test resource in a test build to exercise graceful fallback.

No user Mac was opened. No push, merge, publication or external paid API use.
