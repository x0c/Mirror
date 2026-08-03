@preconcurrency import AVFoundation
import Foundation

private enum CameraPreferenceKey {
    static let isMirrored = "mirror.preview.isMirrored"
}

final class CameraSessionManager: NSObject, ObservableObject, @unchecked Sendable {
    enum State {
        case idle
        case unauthorized
        case running
        case failed(String)
    }

    @MainActor @Published private(set) var state: State = .idle
    @MainActor @Published private(set) var isMirrored = CameraSessionManager.storedIsMirroredPreference()

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.x0c.mirror.camera")
    @MainActor private var isConfigured = false

    override init() {
        super.init()
    }

    @MainActor
    func toggleMirroring() {
        isMirrored.toggle()
        UserDefaults.standard.set(isMirrored, forKey: CameraPreferenceKey.isMirrored)
    }

    private static func storedIsMirroredPreference() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: CameraPreferenceKey.isMirrored) != nil else {
            return true
        }
        return defaults.bool(forKey: CameraPreferenceKey.isMirrored)
    }

    func start() {
        Task {
            await prepareIfNeeded()
            let currentState = await MainActor.run { state }
            if case .unauthorized = currentState {
                return
            }
            if case .failed = currentState {
                return
            }

            sessionQueue.async { [session] in
                guard !session.isRunning else {
                    return
                }
                session.startRunning()
                Task { @MainActor in
                    self.state = .running
                }
            }
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            guard session.isRunning else {
                return
            }
            session.stopRunning()
        }

        Task { @MainActor in
            if case .running = state {
                state = .idle
            }
        }
    }

    private func prepareIfNeeded() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            await configureSessionIfNeeded()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                await configureSessionIfNeeded()
            } else {
                await MainActor.run {
                    state = .unauthorized
                }
            }
        default:
            await MainActor.run {
                state = .unauthorized
            }
        }
    }

    private func configureSessionIfNeeded() async {
        let alreadyConfigured = await MainActor.run { isConfigured }
        guard !alreadyConfigured else {
            return
        }

        do {
            let session = self.session
            try await withCheckedThrowingContinuation { continuation in
                sessionQueue.async {
                    do {
                        session.beginConfiguration()
                        session.sessionPreset = .high

                        if let input = session.inputs.first {
                            session.removeInput(input)
                        }

                        guard let device = Self.makePreferredCameraDevice() else {
                            throw CameraError.noCamera
                        }

                        let input = try AVCaptureDeviceInput(device: device)
                        guard session.canAddInput(input) else {
                            throw CameraError.cannotAddInput
                        }

                        Self.enableCenterStageIfSupported(for: device)
                        session.addInput(input)
                        session.commitConfiguration()
                        continuation.resume()
                    } catch {
                        session.commitConfiguration()
                        continuation.resume(throwing: error)
                    }
                }
            }

            await MainActor.run {
                isConfigured = true
                state = .idle
            }
        } catch {
            await MainActor.run {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private static func makePreferredCameraDevice() -> AVCaptureDevice? {
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .deskViewCamera,
            .continuityCamera,
            .external
        ]

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .front
        )

        return discovery.devices.first ?? AVCaptureDevice.default(for: .video)
    }

    private static func enableCenterStageIfSupported(for device: AVCaptureDevice) {
        guard #available(macOS 12.3, *), device.activeFormat.isCenterStageSupported else {
            return
        }

        AVCaptureDevice.centerStageControlMode = .cooperative
        AVCaptureDevice.isCenterStageEnabled = true
    }
}

private enum CameraError: LocalizedError {
    case noCamera
    case cannotAddInput

    var errorDescription: String? {
        switch self {
        case .noCamera:
            return "没有找到可用的前置摄像头。"
        case .cannotAddInput:
            return "无法把摄像头接入采集会话。"
        }
    }
}
