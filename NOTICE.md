# Third-party notices

This app adapts the capture button, circular buttons, button scale interaction, colors,
and icons from Mijick/Camera, commit 0f02348fcc8fbbc9224c7fbf444f182dc25d0b40.
Copyright ©2024 Mijick. Original author: Tomasz Kurylik.
https://github.com/Mijick/Camera

Licensed under the Apache License, Version 2.0. The complete license is included in
ThirdParty/Mijick-LICENSE. Adapted Swift components are marked in MijickControls.swift.
The controls now drive a dedicated streaming camera engine. Photo capture, movie
recording, captured-media review, and save-to-Photos workflows are omitted.

The original Mijick library is not linked: its visual components are adapted directly
to avoid creating a second capture session. The user's existing Mijick fork is unchanged.
