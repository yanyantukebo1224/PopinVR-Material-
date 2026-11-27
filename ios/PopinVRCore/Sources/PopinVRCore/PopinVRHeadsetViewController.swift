import ARKit
import AVFoundation
import CoreML
import MetalKit
import UIKit

/// Drop-in iOS view controller for PopinVR.
/// The ordinary phone UI stays hidden. A three-finger touch-and-swipe is the
/// deliberate escape gesture for the small emergency menu.
public final class PopinVRHeadsetViewController: UIViewController {
    private var headTracker: PopinVRHeadTracker?
    private var renderer: PopinVRStereoHeadsetRenderer?
    private var metalView: MTKView?
    private var handPipeline: PopinVRHandTrackingPipeline?
    private let assetSetup = PopinVRAssetSetup()
    private var statusLabel: UILabel?
    private var emergencyMenu: UIVisualEffectView?
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

        // No visible phone controls during normal VR use. The menu can only be
        // revealed by keeping three fingers on the display and swiping.
        let revealMenu = UIPanGestureRecognizer(target: self, action: #selector(handleThreeFingerMenuGesture(_:)))
        revealMenu.minimumNumberOfTouches = 3
        revealMenu.maximumNumberOfTouches = 3
        revealMenu.cancelsTouchesInView = false
        revealMenu.delaysTouchesBegan = false
        view.addGestureRecognizer(revealMenu)

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

    @objc private func handleThreeFingerMenuGesture(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .began else { return }
        toggleEmergencyMenu()
    }

    private func toggleEmergencyMenu() {
        if let menu = emergencyMenu {
            menu.removeFromSuperview()
            emergencyMenu = nil
            return
        }

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.layer.cornerRadius = 22
        blur.clipsToBounds = true

        let title = UILabel()
        title.text = "PopinVR Control"
        title.textColor = .white
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        title.textAlignment = .center

        let hint = UILabel()
        hint.text = "Three-finger gesture detected"
        hint.textColor = UIColor.white.withAlphaComponent(0.72)
        hint.font = .systemFont(ofSize: 12)
        hint.textAlignment = .center

        let close = UIButton(type: .system)
        close.setTitle("VRに戻る", for: .normal)
        close.setTitleColor(.white, for: .normal)
        close.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        close.backgroundColor = UIColor.white.withAlphaComponent(0.16)
        close.layer.cornerRadius = 12
        close.addTarget(self, action: #selector(closeEmergencyMenu), for: .touchUpInside)
        close.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let stack = UIStackView(arrangedSubviews: [title, hint, close])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        blur.contentView.addSubview(stack)
        view.addSubview(blur)
        NSLayoutConstraint.activate([
            blur.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            blur.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            blur.widthAnchor.constraint(equalToConstant: 280),
            stack.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: blur.contentView.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor, constant: -18)
        ])
        emergencyMenu = blur
    }

    @objc private func closeEmergencyMenu() {
        emergencyMenu?.removeFromSuperview()
        emergencyMenu = nil
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
