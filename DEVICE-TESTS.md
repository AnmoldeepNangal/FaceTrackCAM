# iPhone acceptance checks

These checks have not been completed by the coding agent. They require your device.

| Check | Expected result |
| --- | --- |
| Fresh install; deny camera | Clear error and Open Settings action; no crash |
| Grant camera, return to app | Live preview starts |
| Start/stop/restart stream | OBS connects with the current token; old token is rejected |
| Switch front/rear and physical lenses | Preview and OBS recover; exposure controls remain usable |
| Rotate phone in both output formats | Upright frame, fixed selected dimensions, no stretch |
| Mirror settings with visible printed text | Preview and stream follow their separate settings |
| Move face to all four image edges | No black crop edges or out-of-bounds jumps |
| Two people; reorder positions | Verify position-based target choice is suitable |
| Leave frame for more than a second | View widens smoothly |
| Blur and custom image | Subject remains visible; preview matches OBS |
| Pick a large/rotated photo, cancel picker | Photo orientation correct; cancel leaves app usable |
| Slow client or disconnected Wi-Fi | No accumulating frame queue; viewer count clears |
| Connect more than three viewers | Extra stream request gets 503 |
| Dim and wake | Stream continues; original brightness returns |
| Lock phone or background app | Stream stops; return and start manually |
| Camera interrupted by call/another app | No crash; retry or foreground restores preview |
| USB with Wi-Fi disabled | OBS receives video through loopback URL |
| Unplug/reconnect USB | Reconnect or restart helper restores video |
| 30-minute stream with effects | Record FPS, heat, memory, latency, and battery drain |

Do not mark these passed on the strength of a successful compile alone.
