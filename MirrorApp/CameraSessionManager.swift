import Foundation
import Observation
@preconcurrency import AVFoundation

private enum CameraPreferenceKey {
    static let isMirrored = "mirror.preview.isMirrored"
}

@MainActor
@Observable
final class CameraSessionManager {
    enum State {
        case idle
        case unauthorized
        case running
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var isMirrored = CameraSessionManager.storedIsMirroredPreference()

    /// 采集会话交给后台队列管理，不参与界面观察。
    nonisolated(unsafe) let session = AVCaptureSession()

    nonisolated private let sessionQueue = DispatchQueue(label: "com.x0c.mirror.camera")
    private var isConfigured = false

    init() {
        observeSessionRuntimeErrors()
    }

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

            switch state {
            case .unauthorized, .failed:
                return
            default:
                break
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

        if case .running = state {
            state = .idle
        }
    }

    /// 系统设置里重新打开摄像头授权后，回到应用时自动恢复采集。
    func recheckAuthorization() {
        guard case .unauthorized = state else {
            return
        }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            return
        }

        stop()
        start()
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
                state = .unauthorized
            }
        default:
            state = .unauthorized
        }
    }

    private func configureSessionIfNeeded() async {
        guard !isConfigured else {
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

            isConfigured = true
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// 用户在系统设置里撤销授权时，正在运行的采集会被系统打断并上报错误；
    /// 把这类错误识别为权限问题，切到降级态而不是表现成莫名的黑屏。
    private func observeSessionRuntimeErrors() {
        NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionRuntimeError,
            object: session,
            queue: .main
        ) { [weak self] notification in
            guard
                let self,
                let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError,
                error.domain == AVFoundationErrorDomain,
                error.code == AVError.Code.contentIsNotAuthorized.rawValue
            else {
                return
            }

            Task { @MainActor in
                self.state = .unauthorized
                self.stop()
            }
        }
    }

    private nonisolated static func makePreferredCameraDevice() -> AVCaptureDevice? {
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

    private nonisolated static func enableCenterStageIfSupported(for device: AVCaptureDevice) {
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