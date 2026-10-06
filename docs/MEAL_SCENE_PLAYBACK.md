# Meal scene playback

The user-provided animation is split into five lossless APNG scenes. The manifest,
APNG files and finished still are included in Resources/MealScenes.

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
- `Resources/MealScenes/`: five APNG scenes, the finished still and the manifest.

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

Verified on Mac with Xcode 27.0 (27A266a), Swift 6.4, iOS Simulator 27.0 SDK:

- All 280 PiyoCore XCTest cases passed, including 8 scene playback tests.
- Generic iOS Simulator build succeeded with signing disabled.
- The actual app bundle manifest decoded through PiyoCore; all resources resolved.
- macOS ImageIO decoded all 101 APNG frames at 640x360 and 100ms each (10.1s total).
- APNGs and manifest remain byte-identical in the bundle; the Xcode-compressed
  finished still has identical decoded pixels.
- Scene duration now sums milliseconds before converting to seconds to avoid
  repeated floating-point addition errors. Existing tests are unchanged.

No GUI was opened. iOS on-screen playback, actual background/foreground and
Reduce Motion transitions, and non-piyo fallback on screen remain unverified.
An attempted physical-iPad build was blocked by disabled Developer Mode and
an unset Development Team; no app was installed and device data was unchanged.
