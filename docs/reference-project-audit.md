# PopinVR reference-project audit

This document records the external implementation patterns reviewed for the iOS runtime. They are references, not dependencies; PopinVR keeps its own native implementation and coordinate contracts.

## Primary references

### Afterglow — native Swift / Metal / ARKit
Repository: https://github.com/blaineam/Afterglow  
License shown by its repository: Apache-2.0.

Useful areas reviewed:

- `app/Afterglow/Tracking/ARController.swift`: ARKit frame ingestion, camera intrinsics, frame timestamps, optional scene-depth delivery, and asynchronous hand-frame submission.
- `app/Afterglow/Tracking/PosePredictor.swift`: combines ARKit pose samples with CoreMotion attitude history to predict orientation to display time; scores predicted-vs-raw pose error.
- `app/Afterglow/Tracking/HeadSmoother.swift`: quaternion smoothing with jump detection.
- `app/Afterglow/Stereo/LensDistortion.swift`, `PolynomialRadialDistortion.swift`, and `ViewerParams.swift`: physical viewer profile, asymmetric per-eye FOV, Cardboard radial distortion, and a post-render distortion mesh.
- `app/Afterglow/Hands/HandTracker.swift`: asynchronous, bounded hand inference; two-hand Vision requests; confidence-aware tracking; temporal hold/prediction; pinch hysteresis.
- `app/Afterglow/Hands/HandGeometry.swift`: uses camera intrinsics and a hand-shape prior to place 2D joints in a metric camera coordinate frame.

Hardware caveat: the README says the app is built and tested on iPhone 18 Pro Max. Its optional scene-depth path uses LiDAR to calibrate palm size. PopinVR targets iPhone 16e, which has no LiDAR, so that depth-dependent calibration cannot be assumed. The useful transferable parts are the tracking architecture, filtering, camera-intrinsics geometry and stereo/lens math—not its hardware assumptions.

### CardboardXR — cross-platform system architecture
Repository: https://github.com/brenpoly/CardboardXR

Useful areas reviewed:

- The app separates Stereo, Hands, Interaction, Tracking and Demos.
- AR Foundation is the source of 6DoF pose and camera frames; stereo views and lens distortion are rendered by the app.
- Hand tracking is decoupled from interaction and feeds XR Hands / interaction components.
- The hand model is rate-limited so inference cannot build an unbounded queue behind camera frames.
- Its iPhone 15 Pro validation includes LiDAR-based hand-size assistance; this is not a direct performance or compatibility guarantee for iPhone 16e.

### ARKit Cardboard examples
Repositories reviewed:

- https://github.com/andrewnakas/ARKit-Cardboard-VR
- https://github.com/hanleyweng/iOS-ARKit-Headset-View
- https://github.com/palle-k/GVRSCNRenderer

These are older SceneKit / Google VR examples. They are useful for historical stereo-camera conventions, but their old iOS/Xcode targets and known distortion/stutter caveats make them poor foundations for PopinVR.

## PopinVR decisions

1. Keep ARKit world tracking as the primary 6DoF position-and-orientation source.
2. Add CoreMotion-based late pose prediction only after measuring ARKit-to-display latency. Prediction must be validated against later ARKit poses, not assumed to improve tracking.
3. Treat physical headset calibration as a first-class setting: IPD, screen dimensions, lens-to-screen distance, vertical lens offset, radial distortion coefficients and per-eye FOV.
4. Use a post-render distortion mesh; do not bake lens distortion into the 3D scene geometry.
5. Keep camera frame ingestion, hand inference, world placement, interaction and rendering on separate bounded stages. Drop stale hand frames rather than allowing latency to grow.
6. On iPhone 16e, use monocular HaMeR/SOMA-X scale/depth estimates and temporal constraints. Do not require ARKit sceneDepth or LiDAR.
7. Use Vision 2D hand pose as an initial/fallback detector. The intended full hand path is detector + HaMeR Core ML parameters + SOMA-X geometry + a skinned 3D mesh.

## Current implementation status

- Implemented in this branch: ARKit 6DoF pose provider, configurable off-axis stereo eye matrices, a Metal SBS world-grid preview, Vision two-hand 2D keypoints, Core ML HaMeR model adapter, and a 3D mesh-frame data contract.
- Not yet implemented: calibrated Cardboard lens warp, late pose prediction, HaMeR-equivalent crop preprocessing, fasthands detector adapter, MANO-to-SOMA-X regressor/geometry on iOS, 3D hand mesh GPU rendering, interaction/pinch tracking, and app-shell integration.
- Not yet verified: Xcode build, iPhone 16e runtime, tracking accuracy, sustained frame rate, latency, thermal behavior, or visual alignment through physical lenses.

No upstream source files have been copied into PopinVR. Reuse of third-party code or assets will require a separate license and attribution review before integration.
