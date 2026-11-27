# PopinVRCore (iOS foundation)

This Swift package is the native iOS runtime foundation being developed alongside the fasthamer reference implementation.

## Implemented in this branch

- `PopinVRHeadTracker`: ARKit world tracking and a thread-safe latest 6DoF camera pose; camera frames are exposed to asynchronous consumers.
- `PopinVRStereoRig`: parallel-axis, off-axis left/right eye matrices.
- `PopinVRLensProfile`: physical screen/viewer dimensions, Cardboard-style radial distortion model, per-eye FOV and screen-to-texture mapping.
- `PopinVRStereoHeadsetRenderer`: Metal side-by-side grid preview and a 3D SOMA-X mesh draw path.
- `PopinVRHeadsetViewController` / `PopinVRHeadsetView`: UIKit and SwiftUI entry points for a camera-permission-gated smoke test.
- `PopinVRVisionHandTracker`: Vision two-hand 2D keypoints.
- `PopinVRHandTrackingPipeline`: bounded asynchronous frame processing; drops frames while busy instead of building a stale queue.
- `PopinVRHaMeRPreprocessor`: native RGB crop and normalization stage.
- `PopinVRHaMeRCoreMLModel`: Core ML adapter for HaMeR parameter outputs.
- `PopinVRHandMeshFrame`: contract for 2,859-vertex / 5,692-face SOMA-X mesh frames.
- `PopinVRSOMA`: vendored plain-C SOMA-X geometry stage from the MIT-licensed fasthamer source, exposed as a SwiftPM C target.

## Host app setup

Add this package to an iOS 17+ Xcode app. The host app must provide:

- `NSCameraUsageDescription` in Info.plist.
- A landscape headset layout and a physical viewer profile calibrated to the actual screen and lenses.
- The HaMeR and SOMA-X model assets. Large model weights are deliberately not committed to this repository.

The first smoke test can be shown with `PopinVRHeadsetView()`. The ARKit session starts after camera permission is granted.

## Important limitations — not a finished VR runtime yet

- The current renderer draws a side-by-side stereo preview. The radial-distortion mapping exists, but the post-render lens-warp pass is not yet wired into the renderer.
- The default lens profile is a Cardboard-v2 starting point, not a measurement of the user's physical headset. IPD, screen dimensions, lens distance, vertical offset and distortion need calibration.
- ARKit 6DoF pose is not yet late-predicted with CoreMotion. No motion-to-photon latency has been measured.
- The Vision pipeline is connected to ARKit frames. The controller currently constructs it without a loaded HaMeR model, so the default smoke test only produces 2D hand keypoints.
- The HaMeR cropper does not yet include fasthamer's optional antialias pre-blur and has not been numerically compared with Python reference tensors.
- HaMeR Core ML inference can return MANO parameters, but the mano2soma-x regressor, wrist-frame conversion, learned vertex correctives, SOMA asset loader and C geometry wrapper are not yet connected end-to-end.
- The Metal renderer can accept a valid SOMA-X mesh frame, but no live HaMeR-to-SOMA-X mesh currently reaches it.
- No Xcode build, iPhone 16e runtime, lens alignment, two-hand accuracy, sustained FPS, latency, memory or thermal measurements have been completed in this environment.

## iPhone 16e constraints

The target phone has no LiDAR and no ultra-wide camera. PopinVR must therefore use ARKit visual-inertial world tracking and monocular hand reconstruction. Do not make sceneDepth a required dependency. HaMeR/SOMA-X scale estimates and temporal constraints are the intended route for 3D hand placement.

## Validation order

1. Build the package with Xcode for iOS Simulator.
2. Run the headset grid preview on iPhone 16e and verify translation and rotation independently.
3. Calibrate lens geometry through the actual viewer.
4. Compare the native HaMeR crop tensor with fasthamer's Python output.
5. Verify Core ML outputs against Python.
6. Port and verify the mano2soma-x regressor and SOMA-X geometry against Python vertices/joints.
7. Feed both meshes to the Metal renderer and verify handedness, winding and camera-space placement.
8. Measure sustained latency, frame pacing, memory and thermal behavior on-device.

Until these gates pass, this repository contains an implementation scaffold and partial native pipeline, not a completed headset/hand-tracking product.
