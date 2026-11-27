import ARKit
import AVFoundation
import CoreML
import MetalKit
import UIKit

/// Drop-in iOS view controller for PopinVR.
/// Model installation is a blocking first-run gate: AR tracking and the headset
/// renderer are not started until HaMeR + SOMA-X assets are verified and compiled.
public final class PopinVRHeadsetViewController: UIViewController {
    private var headTracker: PopinVRHeadTracker?
    private var renderer: PopinVRStereoHeadsetRenderer?
    private var metalView: MTKView?
    private var handPipeline: PopinVRHandTrackingPipeline?
    private let assetSetup = PopinVRAssetSetup()
    private var statusLabel: UILabel?
    private var hasStartedSession = false
    private var isPreparingAssets = false
    private var preparedAssets: PopinVRAssetSetup.Assets?

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
        tracker.onFrame = { [weak self] pixelBuffer, timestamp, intrinsics, cameraTransform in
            self?.handPipeline?.submit(
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
        prepareAssetsThenRequestCamera()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        headTracker?.pause()
        hasStartedSession = false
    }

    private func prepareAssetsThenRequestCamera() {
        guard !isPreparingAssets, preparedAssets == nil else {
            if preparedAssets != nil { startWhenAuthorized() }
            return
        }
        isPreparingAssets = true
        showStatus("PopinVR first-run setup\nDownloading and preparing hand-tracking models…\nThis is required before VR can start.")
        Task { [weak self] in
            guard let self else { return }
            do {
                let assets = try await assetSetup.prepare()
                let model = try PopinVRHaMeRCoreMLModel(compiledModelAt: assets.compiledHaMeRURL)
                preparedAssets = assets
                handPipeline = PopinVRHandTrackingPipeline(
                    maximumInferenceRate: 20,
                    maximumHands: 2,
                    haMeRModel: model
                )
                isPreparingAssets = false
                removeStatus()
                startWhenAuthorized()
            } catch {
                isPreparingAssets = false
                showStatus("PopinVR setup failed\n\(error.localizedDescription)\n\nCheck your connection and restart setup.")
            }
        }
    }

    private func startWhenAuthorized() {
        guard preparedAssets != nil, !hasStartedSession, let tracker = headTracker else { return }
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
        let label = statusLabel ?? UILabel()
        label.text = message
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.backgroundColor = UIColor.black.withAlphaComponent(0.82)
        label.layer.cornerRadius = 14
        label.layer.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        if label.superview == nil {
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
                label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
            ])
        }
        statusLabel = label
    }

    private func removeStatus() {
        statusLabel?.removeFromSuperview()
        statusLabel = nil
    }
}
