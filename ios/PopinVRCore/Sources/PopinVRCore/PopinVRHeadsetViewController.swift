import ARKit
import AVFoundation
import MetalKit
import UIKit

/// Drop-in iOS view controller for the first PopinVR headset smoke test.
/// The host app must include NSCameraUsageDescription in its Info.plist.
public final class PopinVRHeadsetViewController: UIViewController {
    private var headTracker: PopinVRHeadTracker?
    private var renderer: PopinVRStereoHeadsetRenderer?
    private var metalView: MTKView?
    private var handPipeline: PopinVRHandTrackingPipeline?
    private var hasStartedSession = false

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let metalView = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        metalView.translatesAutoresizingMaskIntoConstraints = false
        metalView.isPaused = false
        metalView.enableSetNeedsDisplay = false
        view.addSubview(metalView)
        NSLayoutConstraint.activate([
            metalView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            metalView.topAnchor.constraint(equalTo: view.topAnchor),
            metalView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        self.metalView = metalView

        let tracker = PopinVRHeadTracker()
        guard let renderer = PopinVRStereoHeadsetRenderer(view: metalView, headTracker: tracker) else {
            showStatus("Metal renderer unavailable")
            return
        }
        self.headTracker = tracker
        self.renderer = renderer
        let handPipeline = PopinVRHandTrackingPipeline(maximumInferenceRate: 20, maximumHands: 2)
        self.handPipeline = handPipeline
        tracker.onFrame = { [weak handPipeline] pixelBuffer, timestamp, intrinsics, cameraTransform in
            handPipeline?.submit(
                pixelBuffer: pixelBuffer,
                timestamp: timestamp,
                orientation: .up,
                cameraIntrinsics: intrinsics,
                worldFromCamera: cameraTransform
            )
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startWhenAuthorized()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        headTracker?.pause()
        hasStartedSession = false
    }

    private func startWhenAuthorized() {
        guard !hasStartedSession, let tracker = headTracker else { return }
        guard ARWorldTrackingConfiguration.isSupported else {
            showStatus("ARKit world tracking is not supported on this device")
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession(tracker)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.startSession(tracker)
                    } else {
                        self.showStatus("Camera permission is required for 6DoF tracking")
                    }
                }
            }
        case .denied, .restricted:
            showStatus("Enable camera access for PopinVR in Settings")
        @unknown default:
            showStatus("Camera permission state is unavailable")
        }
    }

    private func startSession(_ tracker: PopinVRHeadTracker) {
        guard !hasStartedSession else { return }
        do {
            try tracker.start()
            hasStartedSession = true
        } catch {
            showStatus("Could not start ARKit world tracking: \(error.localizedDescription)")
        }
    }

    private func showStatus(_ message: String) {
        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
    }
}
