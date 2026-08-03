import AVFoundation
import AppKit
import SwiftUI

struct CameraPreviewView: NSViewRepresentable {
    let sessionManager: CameraSessionManager
    var isMirrored: Bool

    func makeNSView(context: Context) -> PreviewHostingView {
        let view = PreviewHostingView(sessionManager: sessionManager)
        view.isMirrored = isMirrored
        return view
    }

    func updateNSView(_ nsView: PreviewHostingView, context: Context) {
        nsView.sessionManager = sessionManager
        nsView.isMirrored = isMirrored
    }
}

final class PreviewHostingView: NSView {
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private var resizeState: MirrorResizeState?

    override var mouseDownCanMoveWindow: Bool { false }

    var sessionManager: CameraSessionManager {
        didSet {
            previewLayer.session = sessionManager.session
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
        updateMirroring()
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
        if event.clickCount == 2 {
            (window?.windowController as? MirrorWindowController)?.hideMirror()
            return
        }

        if let state = makeResizeStateIfNeeded(with: event) {
            resizeState = state
            (window?.windowController as? MirrorWindowController)?.beginInteractiveResize()
            (window as? MirrorPanel)?.activeResizeCursor = state.cursor
            syncResizeCursor(state.cursor)
            return
        }

        window?.performDrag(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard var resizeState, let window else {
            return
        }

        syncResizeCursor(resizeState.cursor)
        window.resizeMirror(using: event, state: &resizeState)
        self.resizeState = resizeState
    }

    override func mouseUp(with event: NSEvent) {
        let didResize = resizeState != nil
        resizeState = nil
        if didResize {
            (window?.windowController as? MirrorWindowController)?.endInteractiveResize()
        }
        (window as? MirrorPanel)?.activeResizeCursor = nil
        syncResizeCursor(with: event)
        super.mouseUp(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        window?.adjustMirrorOpacity(with: event)
    }

    private func updateMirroring() {
        previewLayer.setAffineTransform(.identity)

        guard let connection = previewLayer.connection else {
            return
        }

        connection.automaticallyAdjustsVideoMirroring = false
        guard connection.isVideoMirroringSupported else {
            return
        }

        connection.isVideoMirrored = isMirrored
    }
}
