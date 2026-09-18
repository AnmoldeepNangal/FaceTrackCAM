Continue the interrupted FaceTrackCAM release pass from the CURRENT repository state.

Branch:
codex/mijick-obs-streaming

Read AGENTS.md first.

DO NOT restart the audit or redo completed work.

The previous Astra session already completed the main investigation and made several fixes. Its progress was:

COMPLETED / ALREADY INVESTIGATED
- Found missing launch-screen/full-screen declaration that could cause iOS compatibility-area letterboxing.
- Added/fixed the full-screen launch configuration.
- Added build verification for that configuration.
- Fixed/improved the top-right moon/low-light control styling/placement.
- Fixed Host-mode camera lifecycle so leaving Host explicitly stops the camera.
- Fixed encoder shutdown/restart so occupied frame slots do not remain stuck.
- Reduced unnecessary preview redraws of unchanged frames.
- Fixed encoded-frame-drop recovery so OBS waits for a fresh keyframe instead of receiving dependent frames after a missing reference.
- Core tests passed.
- iPhone build passed.
- Added simulator layout checks targeting iPhone 13 Pro and iPhone 17 Pro Max.
- Packaged app was verified to contain the full-screen launch declaration.

The layout tests then uncovered the remaining black-bar root cause.

LATEST CONFIRMED ROOT CAUSE
The app window is now full-screen, but the parent SwiftUI layout still constrains the camera preview to the SAFE AREA.

The previous agent began fixing this by:
- moving the full-screen camera/preview layout to the ROOT
- applying safe-area padding only to UI controls/overlays
- keeping the preview/rendering surface edge-to-edge

It was interrupted by usage limits immediately after editing the relevant file and requesting permission to continue.

FIRST ACTIONS
1. Inspect git status.
2. Inspect git diff.
3. Inspect recent commits.
4. Preserve all existing changes.
5. Determine whether the final root-layout edit is complete or partially applied.
6. Continue from that exact point.

DO NOT discard, reset, or recreate completed work.

==================================================
PRIMARY TASK — FINISH BLACK-BAR FIX
==================================================

Finish the confirmed layout fix.

Required architecture:

FULL-SCREEN ROOT
    ↓
camera / Metal preview fills entire display
    ↓
UI controls/overlays independently respect safe-area insets

The camera preview itself must NOT inherit safe-area constraints.

Requirements:
- no artificial top black bar
- no artificial bottom black bar
- preview/rendering surface extends edge-to-edge
- controls remain inside appropriate safe areas
- no hard-coded iPhone dimensions
- no device-specific offsets
- works naturally on iPhone 13 Pro
- works naturally on iPhone 17 Pro Max
- orientation behavior remains correct
- existing camera crop/aspect behavior remains appropriate

Do not solve this with arbitrary negative padding or offsets.

Fix the root hierarchy correctly.

==================================================
LAYOUT TEST
==================================================

A simulator regression test already exists.

The previous tests initially measured the wrong SwiftUI region, then were changed to inspect the actual native/Metal preview using a synthetic camera frame.

Keep that approach.

The final test must verify the ACTUAL rendered preview surface fills the full simulator display rather than merely testing an outer SwiftUI container.

Keep strict assertions for:
- iPhone 13 Pro
- iPhone 17 Pro Max

Also verify that important controls such as the moon control and toolbar remain within usable screen/safe-area bounds.

Do not weaken the assertion merely to make the test pass.

==================================================
AFTER THE LAYOUT FIX
==================================================

Do NOT perform another general bug/performance audit.

That work was already done.

Only:
1. finish the root layout fix
2. finish/fix the layout regression test if necessary
3. check compilation
4. run existing core tests
5. run the iPhone build
6. run the simulator layout tests
7. run the existing IPA packaging workflow

If anything fails:
- inspect only the actual failure
- make the smallest relevant fix
- rerun only what is necessary

Do not perform unrelated refactors.

==================================================
PRESERVE
==================================================

Do not regress the fixes already made for:
- full-screen launch configuration
- moon/low-light control
- Host camera shutdown
- encoder restart/frame-slot cleanup
- unchanged-frame rendering optimization
- keyframe recovery after encoded-frame drops
- FaceTrack
- Lock Me
- Auto Widen
- backgrounds
- Host/Remote mode
- H.264 streaming
- wired streaming
- Wi-Fi streaming
- camera controls
- quality controls

==================================================
PHYSICAL DEVICE ITEMS
==================================================

Do not waste API time trying to prove things that require hardware.

These still require physical-device verification later:
- sustained thermal behavior
- actual OBS end-to-end latency
- USB disconnect/reconnect behavior
- multi-hour webcam stability

Build/test what can be verified in CI and clearly leave those items for device testing.

==================================================
FINAL OUTPUT
==================================================

Keep the final response short.

Report only:
- final black-bar root cause/fix
- whether the native preview layout tests passed on both target device sizes
- any additional build-related fix required
- core test result
- iPhone build result
- IPA workflow/result
- files changed
- physical-device tests still required
