# iOS移植性監査: fasthamer → PopinVR

**Status:** 調査段階。iPhone実機でのCore ML実行・速度・精度は未検証。  
**対象:** iPhone 16e / iOS、2ハンド、リアルタイム3Dメッシュ表示。

## 0. このリポジトリの位置づけ

このリポジトリはPopinVR本体のiOSアプリではなく、[VimalMollyn/fasterhamer](https://github.com/VimalMollyn/fasterhamer) のforkです。現在の `main` はfasthamer v0.8.1のPython実装で、Swift/XcodeプロジェクトやiOS向け実装は含まれていません。

したがって、移植対象は「完成済みiOSアプリ」ではなく、HaMeR→SOMA-Xの推論・メッシュ生成パイプラインです。既存のPython実装は参照実装として残し、iOSコードは独立したディレクトリに追加する方針にします。

## 1. 現在のパイプライン

```text
Camera RGB frame
    │
    ▼
Hand detection (fasthands / MediaPipe)
    │  bounding boxes + handedness
    ▼
HaMeR crop preprocessing
    │  256×256 normalized crop
    │  model input is resized/cropped to the Core ML model's declared shape
    ▼
HaMeR Core ML model
    │  cam, global_orient, hand_pose, betas
    ▼
mano2soma-x regressor
    │  SOMA identity / bone scales / 25 joint rotations / root translation
    ▼
SOMA-X geometry stage
    │  forward kinematics + skinning + learned vertex correctives
    ▼
2859 vertices + 5692 triangle faces + 25 SOMA joints
    │
    ▼
Current Python C rasterizer (2D camera overlay)
```

Important source files:

- `src/fasthamer/detection.py`: detector adapters and handedness.
- `src/fasthamer/preprocess.py`: crop transform, normalization, camera conversion.
- `src/fasthamer/inference.py`: Core ML model loading, HaMeR inference, output assembly.
- `src/fasthamer/soma_np.py`: torch-free SOMA-X stage and optional Core ML regressor.
- `src/fasthamer/soma_stage.c`: optimized C geometry implementation.
- `src/fasthamer/types.py`: mesh/joint output contract.
- `src/fasthamer/rendering.py` and `fast_render.c`: current 2D overlay renderer.

## 2. What can be reused, and what cannot

| Part | Current implementation | iOS port direction |
|---|---|---|
| HaMeR network | Core ML `.mlpackage` loaded through Python `coremltools` | Load with Apple's Swift Core ML API. Model compatibility and deployment target must be tested on-device. |
| Hand detector | `fasthands` Core ML wrapper or MediaPipe Tasks | Reuse/convert the detector model only after checking its model I/O and license; alternatively implement a Vision/MediaPipe adapter. |
| Crop + normalization | NumPy + OpenCV | Port the exact crop, mirror, resize, blur and normalization behavior to Swift/Accelerate or Metal. |
| MANO→SOMA regressor | NumPy MLP or a separate Core ML model | Prefer Core ML if the exported model is compatible; otherwise port the small MLP to Swift/Accelerate. |
| SOMA-X geometry | NumPy plus a C backend dynamically compiled as a macOS `.so` | Port the math to a statically linked iOS C target or Swift/Metal. The current runtime `.so` loader and `ctypes` path cannot be used as-is on iOS. |
| 2D mesh overlay | C CPU rasterizer | Do not carry this renderer into PopinVR. Render the mesh as actual 3D geometry using Metal (or a carefully profiled RealityKit path). |

The Python package declares macOS as its operating system and relies on Python, OpenCV, NumPy, `coremltools`, and dynamic C compilation. That is a desktop runtime, not an iOS app runtime.

## 3. Native iOS module boundaries

Keep the port split into small components so model inference and rendering can be tested independently:

1. **FrameInput** — camera pixel buffer, orientation, timestamp, camera intrinsics.
2. **HandDetector** — returns per-hand image-space boxes, handedness, confidence and stable track IDs.
3. **HaMeRCropper** — reproduces the Python crop transform, left-hand mirroring, antialiasing and ImageNet normalization.
4. **HaMeRModel** — Swift Core ML wrapper returning `cam`, `global_orient`, `hand_pose`, and `betas`.
5. **SomaXRegressor** — converts MANO parameters to SOMA-X identity, scales and joint rotations.
6. **SomaXGeometry** — prepares the rest shape, transfers the skeleton, performs forward kinematics and skinning, then applies learned vertex correctives.
7. **HandMeshFrame** — immutable per-frame output containing vertices, faces, joints, handedness, camera transform and timestamp.
8. **PopinVRHandRenderer** — uploads dynamic vertex buffers and draws the mesh in the PopinVR scene.

The first implementation should use a CPU/Accelerate geometry path for correctness, then move only measured bottlenecks to Metal. This keeps the initial port debuggable and avoids rewriting the whole model pipeline at once.

## 4. Coordinate-system contract

The current fasthamer output uses a camera-style frame:

- X points right.
- Y points down.
- Z points forward.
- Length units are meters.
- `vertices` and `keypoints_3d` are hand-centered.
- Add `cam_t` to place them in the full camera frame.
- The full-image projection uses a pinhole camera: `u = f·X/Z + cx`, `v = f·Y/Z + cy`.

ARKit uses a different camera/world convention. The iOS adapter must perform one explicit, tested coordinate conversion at the boundary between HaMeR output and the PopinVR world. Do not scatter sign flips through the renderer. Also account for front/back camera orientation and mirrored preview behavior.

The HaMeR camera estimate is monocular model output, not a physical depth sensor measurement. Treat its scale and translation as estimated values. ARKit camera pose can place the estimated hand relative to the device, but does not magically turn the reconstructed hand into sensor-ground-truth geometry.

## 5. Model assets and licensing gates

The upstream README describes approximately 470 MB for the HaMeR Core ML bundle and approximately 40 MB for SOMA-X assets. These assets are downloaded from upstream releases and are not committed in this repository.

- The source code is MIT-licensed.
- The default SOMA-X hand data is identified upstream as Apache-2.0.
- The mano2soma-x regressor is described upstream as trained using HaMeR research annotations; upstream advises treating it as a research asset.
- The optional MANO model is separately licensed for non-commercial scientific research and must not be bundled as if it were covered by the source-code MIT license.

Before distributing an app or redistributing model assets, verify the exact license and redistribution terms for every model, training dataset and asset. The initial iOS port should target the default SOMA-X path and must not require a MANO account or MANO model file.

## 6. iPhone 16e validation gates

Do not assume the M4 MacBook performance figures in the upstream README apply to iPhone 16e. Validate each gate on the actual target device:

- [ ] The HaMeR `.mlpackage` can be compiled/loaded by the iOS Core ML runtime.
- [ ] The model's declared input and output feature names/shapes match the Swift wrapper.
- [ ] The detector can keep two hands tracked without ID/handedness flicker.
- [ ] Swift preprocessing matches Python reference crops and normalized tensors.
- [ ] HaMeR outputs match the Python reference within an agreed numeric tolerance.
- [ ] SOMA-X vertices/faces match the Python reference (including correctives).
- [ ] Left-hand winding and mirroring are correct.
- [ ] The mesh is anchored consistently to the ARKit camera/world transform.
- [ ] Two hands can be updated and rendered without stale-frame backlog.
- [ ] Thermal behavior, memory use, and sustained frame time are measured on iPhone 16e.

Record separate timings for detection, crop preprocessing, HaMeR inference, SOMA regression, geometry, vertex upload and rendering. End-to-end FPS alone will not identify the bottleneck.

## 7. Recommended implementation order

1. Build a small Swift command-line/test harness on macOS that loads the same Core ML model and validates feature names/shapes.
2. Add an iOS target that runs one static image through the Core ML model.
3. Port preprocessing and compare the model outputs against Python golden fixtures.
4. Port the SOMA-X regressor and geometry stage; compare vertices and joints numerically.
5. Add live camera input and two-hand tracking.
6. Add a Metal renderer with persistent vertex/index buffers.
7. Profile and optimize on iPhone 16e; only then choose CPU, ANE and GPU scheduling.

## 8. Explicit non-goals for the first milestone

- No monocular depth-estimation model in the first pass.
- No attempt to infer absolute world depth from 2D landmarks alone.
- No dependency on a Quest runtime or Android compatibility layer.
- No rewrite of the upstream Python reference implementation.
- No claim of real-time performance until it is measured on the target iPhone.

The first milestone is deliberately narrow: **one image → one or two SOMA-X meshes on iOS, numerically checked against fasthamer**. Live tracking and PopinVR world anchoring come after that.
