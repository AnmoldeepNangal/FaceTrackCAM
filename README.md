# FaceTrackCam

An iOS 17+ camera app for OBS with Mijick's original visual assets and adapted controls.
Includes face framing, background blur/replacement, physical lens selection, automatic
exposure and exposure lock, torch, battery/thermal status, and screen dimming.

## Current validation status

The source is prepared. An iPhone build and automated Swift tests must pass on the
GitHub Mac runner before treating this as a tested build. Physical camera, Wi-Fi,
USB, and long-session tests also require an iPhone. No bug-free guarantee is made.

## Build and install from Windows

1. Use the development branch in your FaceTrackCAM repository. The included workflow
   runs on pushes and can also be started from GitHub's Actions tab.
2. Wait for `Build and test FaceTrackCam` to finish successfully. It runs core tests,
   builds the device and simulator versions, and packages the device app.
3. Download the `FaceTrackCam-unsigned-IPA` artifact and extract `FaceTrackCam.ipa`.
4. Sign/install it using the same iPhone sideloading process used for your existing app.
   The artifact is unsigned; compilation does not supply an Apple signing identity.
5. Open the app and allow Camera and Local Network access when requested.

No microphone permission is requested: this version sends video only. Select your
computer's microphone separately in OBS.

## Wi-Fi to OBS

1. Put the iPhone and OBS computer on the same reachable local Wi-Fi network.
2. Select Landscape (1280×720) or Portrait (720×1280) under Camera before starting.
   Capture targets 30 FPS; processing speed depends on the phone and enabled effects.
3. Tap the large red button to start. Open Connect and copy the Wi-Fi URL.
4. In OBS add **Media Source**, disable **Local File**, and paste the URL in Input.
   Set Input Format to `mpjpeg` if automatic detection does not work.
5. Alternatively use a **Browser Source** with `/view` replacing `/stream.mjpg` in the
   URL. Keep the `?token=...` portion. Set its dimensions to the selected output size.

The access token changes every time streaming starts. Update the OBS URL after a
restart. Access is limited to three simultaneous viewers. This is plain HTTP on the
local network; use a trusted network and do not expose port 8080 to the internet.

## USB to OBS on Windows

The USB connection forwards the same stream; it does not register a Windows webcam.

1. Install Apple's device-support components using your existing iPhone setup.
2. Obtain a compatible `iproxy` from the upstream libimobiledevice/libusbmuxd project.
   This package does not bundle a third-party executable. Official Windows build
   instructions are at https://github.com/libimobiledevice/libusbmuxd#windows.
3. Put `iproxy.exe` and its required DLLs in `USB/`, or pass its path to the helper.
4. Connect the phone with a data cable, unlock it, and accept **Trust This Computer**.
5. In PowerShell, run `./USB/Start-USB.ps1`. If scripts are restricted by your computer,
   run iproxy directly using `iproxy -l 127.0.0.1 18080:8080`.
6. Start streaming on the phone. Copy its USB URL from Connect into OBS Media Source.
7. Keep the helper running and the app open. Turn off Wi-Fi to verify the USB path.

The helper binds only to the computer's loopback address. For multiple attached
phones, pass `-DeviceID` with the intended phone's UDID. After cable reconnection,
restart the helper if your iproxy version does not recover automatically.

## Controls and behavior

- **Tracking:** enable face following and adjust framing intensity. The nearest
  previous face is favored; this is position-based tracking, not identity recognition.
  After one second without a face, framing returns toward the centered wide view.
- **Background:** Off, Blur, or a photo chosen through the system picker. Imported
  photos are resized in memory and are not uploaded to any cloud service.
- **Camera:** choose a physical lens, output shape, independent selfie-preview and
  OBS mirroring, exposure compensation, and automatic or locked exposure.
- **Moon:** dims the screen while streaming. Tap anywhere to restore brightness.
  Streaming prevents auto-lock. Backgrounding the app stops the camera and stream.
- **Thermals:** reduces frame processing when hot and stops streaming at critical
  thermal pressure. Actual temperature in degrees is not exposed by iOS.

## Architecture and attribution

There is one AVFoundation capture session and one serial queue owning camera and
Vision state. Each processed frame is materialized once and shared with the Metal
preview and MJPEG server. Output dimensions stay fixed. The network server retains
at most one pending encoding job and one in-flight send per client; slow frames are
dropped instead of accumulating latency. Partial HTTP headers, authorization, route
validation, timeouts, disconnect cleanup and listener failures are handled explicitly.

Mijick's visual components are adapted directly into `MijickControls.swift`; its
camera manager is not linked. This avoids a second camera session and preserves a
small, dedicated streaming engine. See `NOTICE.md` and `ThirdParty/Mijick-LICENSE`.
The existing Mijick fork and original main app revision remain separate baselines.

## Verification

On a Mac with Swift, run `swift test` for framing and HTTP protocol tests. The GitHub
workflow additionally compiles both iPhone and simulator targets. Follow
`DEVICE-TESTS.md` before relying on the app for a production stream.

Upstream references:
- Mijick Camera: https://github.com/Mijick/Camera
- USB forwarding: https://github.com/libimobiledevice/libusbmuxd#usage
- OBS Browser Source: https://obsproject.com/kb/browser-source
