import AVFoundation
import AppKit
import SwiftUI

struct CameraPreviewView: NSViewRepresentable {
    let sessionManager: CameraSessionManager
    var isMirrored: Bool

    func makeNSView(context: Context) -> PreviewHostingView {
        let view = PreviewHostingView(sessionManager: sessionManager)
        view.isMirrored = isMirrored
        view.updateMirroring()
        return view
    }

    func updateNSView(_ nsView: PreviewHostingView, context: Context) {
        nsView.sessionManager = sessionManager
        nsView.isMirrored = isMirrored
        nsView.updateMirroring()
    }
}

final class PreviewHostingView: NSView {
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private var resizeState: MirrorResizeState?
    nonisolated(unsafe) private var sessionRunningObserver: NSObjectProtocol?

    override var mouseDownCanMoveWindow: Bool { false }

    var sessionManager: CameraSessionManager {
        didSet {
            previewLayer.session = sessionManager.session
            observeSessionRunning()
            updateMirroring()
        }
    }

    var isMirrored = true {
        didSet {
            guard isMirrored != oldValue else {
                return
            }
            updateMirroring()
        }
    }

    init(sessionManager: CameraSessionManager) {
        self.sessionManager = sessionManager
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true

        previewLayer.session = sessionManager.session
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.needsDisplayOnBoundsChange = false
        previewLayer.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "transform": NSNull()
        ]
        layer?.addSublayer(previewLayer)
        observeSessionRunning()
        updateMirroring()
    }

    deinit {
        if let sessionRunningObserver {
            NotificationCenter.default.removeObserver(sessionRunningObserver)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        layer?.cornerRadius = bounds.width / 2
        updateMirroring()
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        MirrorWindowGestures.mouseDown(with: event, in: self, resizeState: &resizeState)
    }

    override func mouseDragged(with event: NSEvent) {
        MirrorWindowGestures.mouseDragged(with: event, in: self, resizeState: &resizeState)
    }

    override func mouseUp(with event: NSEvent) {
        MirrorWindowGestures.finishMouseUp(with: event, in: self, resizeState: &resizeState)
        super.mouseUp(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        MirrorWindowGestures.scrollWheel(with: event, in: self)
    }

    func updateMirroring() {
        // 采集未 running 时 previewLayer.connection 为 nil，此时设 isVideoMirrored 会被丢掉；
        // 菜单勾选已是开启，画面却不翻转，关掉再开会「突然生效」。
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            previewLayer.setAffineTransform(.identity)
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = isMirrored
            return
        }

        previewLayer.setAffineTransform(CGAffineTransform(scaleX: isMirrored ? -1 : 1, y: 1))
    }

    private func observeSessionRunning() {
        if let sessionRunningObserver {
            NotificationCenter.default.removeObserver(sessionRunningObserver)
        }

        sessionRunningObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionDidStartRunning,
            object: sessionManager.session,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateMirroring()
            }
        }
    }
}
