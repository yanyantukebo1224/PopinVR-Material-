# PopinVR spatial runtime plan

## Product behavior

PopinVR should behave like a small standalone headset runtime, not like a phone app with a permanently visible debug HUD.

- The phone's ordinary 2D screen is only a launch/setup surface.
- After setup, the headset view owns the display.
- Home, settings, system/performance, browser, and media controls are world-anchored panels.
- FPS, tracking quality, model state, and diagnostics are shown only inside the optional System panel.
- The browser is a resizable/movable world-space panel. A second panel can remain open for MR passthrough/scene context.

## Implemented foundations

- `PopinVRSpatialWorkspace`: world-space window transforms, visibility state, and ray/plane UV hit testing.
- `PopinVRBrowserWindow`: WKWebView configured for inline media playback and website navigation.
- `PopinVRAssetSetup`: first-run download, SHA-256 verification, extraction, Core ML compilation and blocking setup gate.

## Required next integration work

1. Extend the Metal renderer with a textured quad pipeline. Render every visible panel independently for both eyes using its world transform and eye view-projection matrix.
2. Capture WKWebView snapshots at a capped refresh rate and upload them to a reusable Metal texture. Do not snapshot at the headset refresh rate; browser updates and headset rendering must be decoupled.
3. Route gaze and hand-pointer rays through `PopinVRSpatialWorkspace.hitTest`. Use Vision fingertip landmarks to estimate a camera-space pointer ray and pinch state; map pinch-down to panel click, sustained pinch to drag, and two-finger/scroll gestures to browser scrolling.
4. Add a virtual keyboard and URL/search field as another world-space panel. Keep iOS keyboard/2D chrome out of the normal headset session.
5. Add ARKit camera passthrough as the MR background, then composite stereo panels and virtual content. The current grid renderer is not yet a camera-passthrough compositor.
6. Make browser audio route through the phone's normal audio session while preserving headset rendering. Respect WebKit's protected-media and autoplay limitations.
7. Add a system panel that can be hidden entirely. No diagnostic text should be burned into the default view.

## YouTube and MR caveats

The browser uses WKWebView and loads YouTube's website. It does not bypass YouTube restrictions or DRM. Some protected streams, account flows, casting, picture-in-picture, or fullscreen paths may behave differently from Safari. The browser should expose ordinary page playback and inline video first; protected content support must be validated on a real device.

## Startup gate

The app must not start ARKit or enter the headset runtime until:
- the HaMeR archive passes SHA-256 verification,
- the SOMA-X archive passes SHA-256 verification,
- both archives contain the expected model files,
- the HaMeR Core ML package compiles successfully.

The installer stores assets in Application Support and reuses them on later launches. A failed install leaves the app in setup/error state rather than starting a partially initialized runtime.
