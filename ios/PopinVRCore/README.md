# PopinVRCore (iOS foundation)

This Swift package is the native iOS runtime foundation being developed alongside the fasthamer reference implementation.

## Added in this branch

- ARKit world tracking for 6DoF pose capture.
- Stereo left/right camera rig with off-axis projection.
- Metal side-by-side headset preview and a draw path for SOMA-X mesh frames.
- Vision two-hand 2D keypoints and a bounded asynchronous HaMeR preprocessing/inference pipeline.
- Native Core ML adapter for HaMeR parameter outputs.
- SOMA-X geometry C target and a 3D hand mesh frame contract.
- First-run asset setup: automatically downloads the HaMeR (~470 MB) and SOMA-X (~40 MB) release archives, verifies their SHA-256 digests, extracts them, and compiles both HaMeR and the SOMA-X regressor before the AR session is allowed to start.
- World-anchored spatial-window state and a shared ray/plane hit-test API.
- A WKWebView browser surface configured for inline website playback, including YouTube's normal web player.

## Model setup and licensing

The first-run installer uses the public fasthamer release assets:
- HaMeR model archive: `assets-v2/fasthamer-assets-v2.zip`
- SOMA-X assets archive: `soma-v2/fasthamer-soma-v2.zip`

Both archives are checksum-verified before extraction. The app stores the extracted assets and compiled Core ML model in Application Support. Subsequent launches reuse the verified files and can start offline.

The default SOMA-X path does not require a MANO account. MANO's separately licensed model is not downloaded or included. The installer is a blocking gate: if a download, checksum, extraction, or compilation step fails, the AR headset session is not started.

## Important limitations — not a finished VR runtime yet

- The current renderer is still a side-by-side stereo preview. The spatial-window manager currently defines world-space panel placement and ray hit testing, but it is **not yet connected to the Metal renderer or a hand/gaze input loop**. Therefore the complete Quest-style in-world settings UI is not finished.
- The WKWebView browser surface exists, but its live contents are **not yet composited onto a stereo world-space panel**. YouTube playback inside the eventual in-world browser is the target; DRM, protected video, login and fullscreen behavior remain subject to WebKit and YouTube policy.
- The radial-distortion mapping exists, but the post-render lens-warp pass is not yet wired into the renderer.
- The default lens profile is a Cardboard-v2 starting point, not a measurement of the user's physical headset. IPD, screen dimensions, lens distance, vertical offset and distortion need calibration.
- ARKit 6DoF pose is not yet late-predicted with CoreMotion. No motion-to-photon latency has been measured.
- The controller now loads HaMeR after setup, but the mano2soma-x regressor, wrist-frame conversion, learned vertex correctives, SOMA asset loader and C geometry wrapper are not yet connected end-to-end. HaMeR parameters therefore do not yet become live 3D hand meshes.
- The native cropper has not yet been numerically compared with fasthamer's Python reference tensors.
- No Xcode build, iPhone 16e runtime, lens alignment, two-hand accuracy, sustained FPS, latency, memory or thermal measurements have been completed in this environment.

## iPhone 16e constraints

The target phone has no LiDAR and no ultra-wide camera. PopinVR must therefore use ARKit visual-inertial world tracking and monocular hand reconstruction. Do not make sceneDepth a required dependency.

## Validation order

1. Build the package with Xcode for iOS Simulator.
2. Verify first-run asset download, SHA-256 checks, extraction and Core ML compilation on a device.
3. Run the headset grid preview on iPhone 16e and verify translation and rotation independently.
4. Connect the world-space window renderer and gaze/hand pointer input.
5. Composite the WKWebView browser into the world-space stereo panel and test YouTube playback.
6. Calibrate lens geometry through the actual viewer.
7. Compare native HaMeR preprocessing and Core ML outputs with Python reference outputs.
8. Port and verify mano2soma-x and SOMA-X geometry against Python vertices/joints.
9. Feed both live hand meshes to the Metal renderer and verify handedness, winding and camera-space placement.
10. Measure sustained latency, frame pacing, memory and thermal behavior on-device.

Until these gates pass, this repository contains an implementation scaffold and partial native pipeline, not a completed headset/hand-tracking product.
