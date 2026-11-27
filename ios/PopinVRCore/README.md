# PopinVRCore (iOS foundation)

This Swift package is the native iOS foundation being developed alongside the fasthamer reference implementation.

## Current modules

- `PopinVRHeadTracker`: ARKit world tracking and a thread-safe latest 6DoF camera pose.
- `PopinVRStereoRig`: parallel-axis, off-axis left/right eye camera matrices derived from the ARKit pose.
- `PopinVRLensProfile`: configurable phone/viewer dimensions, Cardboard radial-distortion model, per-eye FOV and the screen-to-texture mapping needed for the post-render lens-warp pass.
- `PopinVRStereoHeadsetRenderer`: a Metal split-screen stereo grid renderer for checking world-locked 6DoF response.
- `PopinVRVisionHandTracker`: native Vision two-hand 2D keypoints. This is only the 2D front-end, not the final 3D hand solution.

## Integration

Add this package to an iOS 17+ Xcode app. The app must provide `NSCameraUsageDescription` in its Info.plist and request camera access before starting ARKit.

Typical flow:

1. Create `PopinVRHeadTracker` and call `start()` while foregrounded.
2. Read `latestPose()` on the render loop.
3. Call `PopinVRStereoRig.views(worldFromCamera:eyeAspectRatio:)` using the per-eye aspect ratio (half the drawable width divided by drawable height).
4. Render each eye into its own half of the headset display using the returned view and projection matrices.
5. Feed camera frames into `PopinVRVisionHandTracker.detect(in:orientation:)` for 2D joints while the HaMeR/SOMA-X mesh path is being ported.

## Important limitations

- This package does not yet contain an app target, headset optical calibration UI, lens-distortion correction, or a complete renderer.
- ARKit camera pose is the device pose in ARKit's world coordinate system. It is not a direct measurement of eye pose inside the headset.
- The stereo rig uses configurable IPD/FOV/convergence defaults. They must be calibrated for the physical headset and display.
- Vision produces 2D keypoints only. It does not provide the final articulated 3D mesh.
- HaMeR/SOMA-X iOS model loading and geometry parity are not yet implemented or validated.
- No iPhone 16e build, runtime, latency, thermal, or tracking-quality measurements have been performed yet.
