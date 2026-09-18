FaceTrackCAM — Settings UI + Remote Background Synchronization Pass

Repository branch:
codex/mijick-obs-streaming

Work from the CURRENT repository state.

Read AGENTS.md first.

IMPORTANT:
The previous release/stabilization work has already succeeded.

Do NOT repeat:
- black-bar/full-screen investigation
- launch-screen investigation
- general performance audit
- H.264 latency audit
- encoder audit
- camera lifecycle audit
- moon-control investigation
- general repository review

Do not undo previous fixes.

This pass has ONLY TWO goals:

1. Fix the remaining Settings UI animation/layout bug.
2. Make Custom Backgrounds + Recent Backgrounds work properly across Host and Remote, including identical visual thumbnail previews.

==================================================
FIRST — INSPECT CURRENT STATE
==================================================

Before editing:

1. Read AGENTS.md.
2. Check git status.
3. Check git diff.
4. Check recent commits.
5. Locate the existing:
   - Settings UI
   - background selector
   - Recent Backgrounds implementation
   - Custom Background / Photos picker implementation
   - Host/Remote synchronization
   - pairing/transport system
   - background storage/cache
6. Reuse the existing architecture wherever practical.

Inspect only files directly relevant to these tasks.

Do not broadly inspect or refactor the repository.

==================================================
TASK 1 — FIX SETTINGS MENU UI BUG
==================================================

There is a remaining visual bug in the Settings glass panel.

Observed behavior:

While Settings expands/collapses or its displayed rows change:
- rows can temporarily overlap
- controls can become compressed
- controls can temporarily occupy incorrect vertical positions
- the glass container and its contents do not always resize together
- transitions can produce visually corrupted intermediate layouts

The final resting layout may look correct, but the transition itself can become visually broken.

Find the ROOT cause.

Inspect relevant code for:
- multiple competing SwiftUI animations
- conditional view insertion/removal
- animated frame/height calculations
- GeometryReader feedback
- transitions combined with animated parent sizing
- stale expanded/collapsed state
- clipping/masking
- changing view identity / .id()
- multiple animation transactions affecting the same hierarchy
- explicit fixed heights fighting intrinsic content sizing
- animation applied separately to parent and child
- asynchronous state changes during transitions

Required result:

Settings must:
- expand smoothly
- collapse smoothly
- resize naturally with its contents
- never overlap rows
- never temporarily squash controls
- never jump/flicker
- remain stable during repeated rapid opening/closing
- preserve current glass/blob design
- preserve current motion/design language

Do NOT simply remove all animations to hide the bug.

Do NOT redesign Settings.

Make the smallest robust fix.

==================================================
TASK 2 — HOST/REMOTE BACKGROUND SYNCHRONIZATION
==================================================

Extend the existing Host/Remote architecture so Custom Backgrounds and Recent Backgrounds behave as a shared feature.

The Remote iPhone must be able to:

1. See the Host's Recent Backgrounds.
2. See the ACTUAL thumbnail preview of every Host recent background.
3. See them in the same order as Host.
4. Tap a Host recent background on Remote and have Host apply it.
5. Choose a NEW custom background from the Remote iPhone's own Photos library.
6. Transfer that background to Host.
7. Have it become part of the shared Recent Backgrounds collection.
8. Have BOTH devices display the same thumbnail afterward.

==================================================
HOST IS AUTHORITATIVE
==================================================

For paired Host/Remote operation, treat Host as the authoritative source for:

- current selected background
- Recent Background list
- Recent Background ordering
- background asset IDs
- which background is currently applied

Remote mirrors this state.

Remote can request changes, but Host confirms/publishes the resulting authoritative state.

This avoids Host and Remote developing conflicting Recent lists.

==================================================
HOST RECENTS MUST VISUALLY APPEAR ON REMOTE
==================================================

This is NOT metadata-only synchronization.

If Host displays:

RECENT BACKGROUNDS

[ beach image ] [ bedroom image ] [ city image ]

Remote should display:

RECENT BACKGROUNDS

[ beach image ] [ bedroom image ] [ city image ]

The user must see the actual image thumbnails.

Do NOT represent Host backgrounds on Remote using:
- filenames
- IDs
- generic image icons
- placeholders after synchronization
- text-only entries

Remote needs enough locally cached image data to render the same thumbnails.

==================================================
SHARE THE EXISTING RECENTS UI
==================================================

Reuse the Host Recent Backgrounds thumbnail component/rendering implementation on Remote whenever practical.

Host and Remote Recent Backgrounds should match in:

- actual image
- ordering
- thumbnail crop
- aspect ratio
- content mode
- corner radius
- spacing
- selected state
- compact horizontal layout
- glass/blob visual treatment

Avoid maintaining two different-looking Recent Background implementations.

If a small shared SwiftUI component/refactor makes Host and Remote reliably identical, that is acceptable.

Do NOT perform unrelated UI refactoring.

==================================================
BACKGROUND MANIFEST
==================================================

Implement a lightweight synchronization model.

Conceptually, Host should publish a Recent Background manifest containing information such as:

- stable background asset ID/hash
- ordering
- currently selected background ID
- required lightweight metadata

Do NOT include full image bytes in this normal state message.

Example conceptual flow:

HOST
  ↓
Recent manifest:
[A hash, B hash, C hash]
selected = B
  ↓
REMOTE
  ↓
compare with local cache

Remote already has A → reuse it
Remote already has B → reuse it
Remote missing C → request C

Host transfers C once.

Remote caches C.

Remote now renders:

[A thumbnail][B thumbnail][C thumbnail]

==================================================
BACKGROUND ASSET IDENTIFIERS
==================================================

Use stable content-based identifiers/hashes where appropriate.

The purpose is to:

- recognize identical assets
- avoid retransmitting images unnecessarily
- allow Remote to determine which Host assets it already has
- deduplicate repeated selections
- survive disconnect/reconnect

Do not rely solely on a Photos-library local asset identifier.

A Photos asset identifier from one iPhone does NOT give the other iPhone access to that image.

The shared identifier should represent the transferred/cached background asset itself.

==================================================
ASSET TRANSFER
==================================================

Do NOT place full image data inside the normal high-frequency Remote control messages.

Keep normal controls lightweight.

Conceptual architecture:

CONTROL/STATE CHANNEL:
- selected background ID
- recent background IDs/order
- transfer request
- transfer status
- clear/remove events
- authoritative Host state

ASSET TRANSFER:
- actual background image payload
- sent only when required

Reuse the existing Host/Remote transport if it can cleanly support asset messages.

Do NOT introduce an unnecessary second networking architecture.

==================================================
REMOTE CONNECT / RECONNECT
==================================================

When Remote connects or reconnects:

Host sends current Recent Background manifest.

Remote compares it against its local background cache.

For every background:

IF PRESENT LOCALLY:
reuse cached image immediately

IF MISSING:
request the missing asset from Host

Host transfers only missing assets.

Remote stores them locally.

Do NOT retransmit the entire Recent collection on every connection.

After synchronization, Remote's Recent Background UI should appear immediately from its local cache on future connections wherever possible.

==================================================
LIVE HOST → REMOTE SYNC
==================================================

If Host adds a custom background:

Host:

[A][B][C]

becomes:

[A][B][C][D]

Remote should automatically update to:

[A][B][C][D]

including the ACTUAL D thumbnail.

If Host:
- changes selected background
- changes Recent ordering
- removes an item
- clears Recents

Remote should update accordingly.

==================================================
REMOTE SELECTS AN EXISTING HOST RECENT
==================================================

Remote must be able to tap any synchronized Recent thumbnail.

Flow:

Remote user taps background B
        ↓
Remote sends "select background B"
        ↓
Host verifies B exists
        ↓
Host applies B
        ↓
Host publishes authoritative selectedBackground = B
        ↓
Remote reflects B as selected

Do NOT send the image again if Host already has B.

==================================================
REMOTE CUSTOM BACKGROUND / PHOTOS PICKER
==================================================

Remote Control mode must expose the same useful Custom Background option.

Desired user experience:

Remote
  ↓
Background
  ↓
Custom / Photos
  ↓
native Photos picker opens ON REMOTE IPHONE
  ↓
user selects image
  ↓
Remote prepares background asset
  ↓
transfer to Host
  ↓
Host stores it
  ↓
Host applies it
  ↓
Host adds it to Recent Backgrounds
  ↓
Host publishes updated manifest
  ↓
Remote receives authoritative state
  ↓
both devices display SAME thumbnail

The Photos picker MUST operate locally on Remote.

Do not attempt to access Remote's Photos library from Host.

Do not attempt to synchronize Photos-library permissions between devices.

Each iPhone accesses only its own Photos library.

==================================================
REMOTE IMAGE PREPARATION
==================================================

Do not automatically transfer an enormous original camera photo if the app does not need that resolution.

Use an appropriate existing image-processing/background-storage path.

Resize/compress intelligently before transfer when appropriate.

Requirements:

- retain enough quality for the app's maximum supported video/background output
- preserve correct orientation
- avoid unnecessary image degradation
- avoid giant transfers
- perform expensive processing off the main thread
- do not freeze Remote UI
- do not interrupt Host camera capture
- do not interrupt OBS streaming

If the existing Host Custom Background pipeline already prepares images appropriately, reuse the same processing logic on Remote where practical.

==================================================
REMOTE-CREATED BACKGROUND BECOMES NORMAL RECENT
==================================================

After successful transfer, a background originally chosen on Remote should no longer behave like a special Remote-only item.

It should become a normal Host-owned Recent Background.

Example:

Host currently:
[A][B][C]

Remote chooses image D from Remote Photos.

After successful transfer:

Host:
[A][B][C][D]

Remote:
[A][B][C][D]

Both devices show the SAME D thumbnail.

Host is now authoritative for D.

On reconnect, D behaves exactly like a background originally selected from Host.

==================================================
THUMBNAIL CONSISTENCY
==================================================

Remote must display previews that visually match Host.

Do not generate a substantially different crop/thumbnail representation on each device.

Prefer either:

1. synchronize/cache the processed background asset and use the same thumbnail rendering rules on both devices

OR

2. synchronize a deterministic thumbnail representation where appropriate

The important result is:

Host thumbnail ≈ Remote thumbnail visually.

Use the same:
- aspect-fill/aspect-fit behavior
- crop
- orientation
- clipping
- corner radius

where possible.

==================================================
CLEAR RECENTS
==================================================

Preserve the existing Clear Recents functionality.

When Host clears Recents:
- Remote receives the new authoritative manifest
- Remote Recent UI clears accordingly
- unused synchronized cache assets may be cleaned up safely

If Remote exposes Clear Recents:
- Remote sends a request to Host
- Host performs/accepts the authoritative change
- Host publishes updated state
- Remote follows that state

Do not allow the two devices to silently diverge.

==================================================
CACHE MANAGEMENT
==================================================

Keep synchronized background storage bounded.

Use the existing Recent Background limit if one already exists.

Do not allow Remote's cache to grow forever.

Do not repeatedly decode full-resolution assets merely to show tiny Recent thumbnails if the existing architecture can cache efficient representations.

Avoid memory spikes.

==================================================
FAILURE HANDLING
==================================================

Background transfer must fail safely.

Handle:

- Remote disconnect during transfer
- Host disconnect during transfer
- incomplete payload
- invalid/corrupted image
- duplicate transfer
- Host already owns asset
- reconnect after failed transfer

Do not add a broken/partial background to Host Recents.

Only publish the new authoritative Recent state after Host has successfully received and stored the asset.

A failed transfer must not crash either app.

==================================================
DO NOT HURT STREAMING PERFORMANCE
==================================================

Background synchronization is secondary to the webcam/video path.

Do NOT allow image synchronization to interfere significantly with:

- camera capture
- FaceTrack
- segmentation
- rendering
- H.264 encoding
- wired streaming
- Wi-Fi streaming
- OBS latency
- Remote control responsiveness

Do not perform heavy image processing synchronously on the camera/encoder hot path.

Do not create unbounded transfer queues.

Only transfer assets when needed.

==================================================
TASK 3 — WORKING MICROPHONE ON/OFF TOGGLE
==================================================

Add a functional Microphone toggle to the existing Settings section.

This must be a REAL audio-streaming control, not merely a visual toggle.

Desired Settings UI:

Microphone     [ ON / OFF ]

Reuse the existing Settings row/toggle visual language so it looks native to
the current FaceTrackCAM glass/blob interface.

==================================================
HOST BEHAVIOR
==================================================

When Microphone is ON:

- capture audio from the Host iPhone microphone
- include that audio in the existing webcam/streaming output wherever the
  current streaming architecture supports audio
- keep audio synchronized appropriately with video
- preserve low-latency webcam behavior

When Microphone is OFF:

- stop sending microphone audio to the streaming destination
- OBS/receiver must not hear Host microphone audio
- avoid unnecessary microphone capture/processing while disabled where
  architecture permits
- video streaming must continue normally
- FaceTrack/camera/background processing must remain unaffected

Do not restart the entire camera unnecessarily when toggling microphone.

==================================================
MICROPHONE PERMISSION
==================================================

Handle iOS microphone permission correctly.

Do not request microphone permission merely because Settings was opened.

Prefer requesting permission when the user first enables Microphone.

Handle:
- permission granted
- permission denied
- permission previously denied/restricted

If permission is unavailable:
- keep actual microphone state OFF
- do not pretend microphone is enabled
- keep UI/state consistent
- fail gracefully without affecting video

Use the appropriate existing iOS permission/audio APIs and project
configuration.

Verify the required microphone usage description exists in the app
configuration. Add it only if missing.

==================================================
HOST / REMOTE SYNCHRONIZATION
==================================================

Microphone enabled state must be part of the existing lightweight Host/Remote
control synchronization.

Host remains authoritative.

When Host changes:

Microphone ON
      ↓
Host publishes state
      ↓
Remote displays Microphone ON

Microphone OFF
      ↓
Host publishes state
      ↓
Remote displays Microphone OFF

Remote must also be able to control it:

Remote user toggles Microphone OFF
      ↓
Remote sends microphone-state request
      ↓
Host changes actual microphone streaming state
      ↓
Host publishes authoritative state
      ↓
Remote reflects confirmed OFF state

The Remote phone's microphone must NOT accidentally become the streamed
microphone.

The toggle on Remote controls the HOST IPHONE microphone.

==================================================
STREAMING / AUDIO PATH
==================================================

Inspect the existing streaming architecture before implementing.

If an audio capture/transport path already exists:
- reuse it
- connect the toggle to the actual audio path

If audio support is partially implemented:
- finish the smallest appropriate implementation

If audio transport is missing:
- implement it using the existing streaming/receiver architecture rather than
  creating an unrelated streaming system

Keep the audio path appropriate for real-time webcam use.

Avoid:
- large audio buffers
- unnecessary latency
- unbounded queues
- blocking camera/encoder threads
- repeated audio-session reconfiguration
- unnecessary processing while microphone is OFF

Do not damage the existing low-latency H.264 video path.

==================================================
STATE / LIFECYCLE
==================================================

Microphone state must remain correct through relevant lifecycle events:

- Host/Remote connection
- Remote reconnect
- stream start/stop
- OBS/receiver reconnect
- camera switching
- app lifecycle transitions supported by the existing app

Clean up microphone/audio resources correctly when streaming/session ends.

Do not leave an orphaned microphone capture session running unnecessarily.

==================================================
SETTINGS UI
==================================================

Place Microphone in the existing Settings section at a logical location.

Reuse the existing toggle/control component if possible.

Do not redesign Settings.

The new row must also work correctly with the Settings animation/layout fix
being performed in this same task.

Make sure adding this row does not reintroduce:
- overlapping Settings rows
- incorrect panel height
- animation glitches
- clipping
- compressed controls

==================================================
TESTING
==================================================

Add focused tests where practical for:

- microphone state defaults correctly
- Host toggle changes requested microphone state
- Remote microphone request reaches Host state logic
- Host authoritative state synchronizes back to Remote
- denied permission cannot result in falsely enabled state
- microphone OFF does not stop video streaming

Do not attempt to fake physical microphone/OBS behavior in unit tests if it
requires real hardware.

==================================================
PHYSICAL VERIFICATION
==================================================

Clearly report that these should be verified on physical devices:

- Host microphone ON → audio reaches OBS/receiver
- Host microphone OFF → audio disappears while video continues
- Remote toggle controls Host microphone
- audio/video synchronization
- reconnect behavior
- microphone permission flow
- sustained latency/thermal behavior with microphone enabled

==================================================
PRESERVE EXISTING FUNCTIONALITY
==================================================

Do NOT regress or redesign already-working:

- full-screen camera layout
- black-bar fix
- launch configuration
- moon/low-light control
- camera lifecycle fixes
- encoder restart cleanup
- dropped-frame/keyframe recovery
- H.264 pipeline
- wired streaming
- Wi-Fi streaming
- FaceTrack
- Lock Me
- Auto Widen
- background segmentation
- Host mode
- Remote mode
- Remote sliders/haptics
- exposure/focus controls
- camera switching
- quality selector
- battery/thermal display
- existing glass/blob design
- existing animations that are not causing the Settings bug

Do not remove features.

Do not perform another release-wide audit.

==================================================
TESTING
==================================================

Add focused tests where practical.

SETTINGS:
- expanded state lays out correctly
- collapsed state lays out correctly
- repeated state transitions do not produce invalid layout

BACKGROUND MANIFEST:
- Host manifest ordering
- selected background ID synchronization
- missing-asset detection

DEDUPLICATION:
- Remote does not request cached asset again
- Host does not store duplicate asset unnecessarily

REMOTE SELECTION:
- tapping synchronized Recent sends correct selection request
- Host publishes authoritative selected state

REMOTE CUSTOM:
- new Remote asset becomes Host Recent after successful transfer
- updated manifest reaches Remote

CLEAR RECENTS:
- Host/Remote state remains consistent

TRANSFER FAILURE:
- incomplete/failed asset is not added to Recents

Do not build a huge new testing architecture just for this task.

==================================================
BUILD / IPA
==================================================

After implementation:

1. Check only modified/relevant code.
2. Run existing core tests.
3. Run relevant new focused tests.
4. Run existing iPhone build.
5. Run the existing IPA workflow.

If something fails:

- inspect the actual compiler/test error
- identify the relevant file/line
- make the smallest fix
- rerun

Do not repeatedly rebuild without making a relevant change.

==================================================
PHYSICAL DEVICE VERIFICATION
==================================================

Do not waste API time trying to simulate everything that fundamentally requires two physical iPhones.

Clearly report anything that still requires physical verification, especially:

- Host → Remote thumbnail appearance
- Remote → Host custom image transfer
- reconnect synchronization
- transfer while OBS is streaming
- responsiveness during image transfer
- Photos picker behavior on Remote
- rapid Settings interaction



==================================================
FINAL RESPONSE
==================================================

Keep the final response concise.

Report ONLY:

1. Settings UI root cause and fix
2. Host → Remote Recent Background preview implementation
3. Remote → Host Custom Background implementation
4. caching/deduplication approach
5. files changed
6. tests passed/failed
7. iPhone build result
8. IPA workflow/result
9. items requiring two-iPhone physical verification
