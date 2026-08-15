import AppKit
import SwiftUI

private enum MirrorPersistenceKey {
    static let originX = "mirror.window.origin.x"
    static let originY = "mirror.window.origin.y"
    static let size = "mirror.window.size"
    static let alpha = "mirror.window.alpha"
}

@MainActor
final class MirrorWindowController: NSWindowController, NSWindowDelegate {
    private let sessionManager: CameraSessionManager
    private var hasPositionedWindow = false
    private var isInteractiveResizeInProgress = false

    init(sessionManager: CameraSessionManager) {
        self.sessionManager = sessionManager

        let contentView = MirrorContentView(sessionManager: sessionManager)
        let hostingView = DraggableHostingView(rootView: contentView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let window = MirrorPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 280),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.ignoresMouseEvents = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.alphaValue = restoredMirrorOpacity()

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    func toggle() {
        guard let window else {
            return
        }

        if window.isVisible {
            hideMirror()
        } else {
            positionWindowIfNeeded(window)
            sessionManager.start()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    func hideMirror() {
        guard let window else {
            return
        }

        persistCurrentFrame()
        sessionManager.stop()
        window.orderOut(nil)
    }

    private func positionWindowIfNeeded(_ window: NSWindow) {
        if restorePersistedFrameIfPossible(for: window) {
            hasPositionedWindow = true
            return
        }

        let currentOrigin = window.frame.origin
        let isOffscreen = !NSScreen.screens.contains { $0.visibleFrame.intersects(window.frame) }

        guard !hasPositionedWindow || isOffscreen || currentOrigin == .zero else {
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main else {
            window.center()
            return
        }

        let frame = screen.visibleFrame
        let origin = NSPoint(
            x: mouseLocation.x - (window.frame.width / 2),
            y: mouseLocation.y - (window.frame.height / 2)
        )

        let clampedOrigin = NSPoint(
            x: min(max(origin.x, frame.minX), frame.maxX - window.frame.width),
            y: min(max(origin.y, frame.minY), frame.maxY - window.frame.height)
        )

        window.setFrameOrigin(clampedOrigin)
        hasPositionedWindow = true
    }

    func windowDidBecomeKey(_ notification: Notification) {
        sessionManager.recheckAuthorization()
    }

    func windowDidMove(_ notification: Notification) {
        guard !isInteractiveResizeInProgress else {
            return
        }
        persistCurrentFrame()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        persistCurrentFrame()
    }

    func windowDidResize(_ notification: Notification) {
        guard !isInteractiveResizeInProgress else {
            return
        }
        persistCurrentFrame()
    }

    func beginInteractiveResize() {
        isInteractiveResizeInProgress = true
    }

    func endInteractiveResize() {
        isInteractiveResizeInProgress = false
        persistCurrentFrame()
    }

    private func persistCurrentFrame() {
        guard let window else {
            return
        }

        let defaults = UserDefaults.standard
        defaults.set(window.frame.origin.x, forKey: MirrorPersistenceKey.originX)
        defaults.set(window.frame.origin.y, forKey: MirrorPersistenceKey.originY)
        defaults.set(window.frame.width, forKey: MirrorPersistenceKey.size)
        defaults.set(window.alphaValue, forKey: MirrorPersistenceKey.alpha)
    }

    private func restorePersistedFrameIfPossible(for window: NSWindow) -> Bool {
        let defaults = UserDefaults.standard

        guard
            defaults.object(forKey: MirrorPersistenceKey.originX) != nil,
            defaults.object(forKey: MirrorPersistenceKey.originY) != nil,
            defaults.object(forKey: MirrorPersistenceKey.size) != nil
        else {
            return false
        }

        let size = min(
            max(defaults.double(forKey: MirrorPersistenceKey.size), Double(MirrorResizeState.minSize)),
            Double(MirrorResizeState.maxSize)
        )
        let frame = NSRect(
            x: defaults.double(forKey: MirrorPersistenceKey.originX),
            y: defaults.double(forKey: MirrorPersistenceKey.originY),
            width: size,
            height: size
        )

        guard NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) else {
            return false
        }

        window.setFrame(frame, display: false)
        return true
    }
}

final class MirrorPanel: NSPanel {
    var activeResizeCursor: NSCursor?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    private var resizeState: MirrorResizeState?
    private var cursorTrackingArea: NSTrackingArea?

    override var mouseDownCanMoveWindow: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let cursorTrackingArea {
            removeTrackingArea(cursorTrackingArea)
        }

        let options: NSTrackingArea.Options = [
            .activeAlways,
            .inVisibleRect,
            .mouseEnteredAndExited,
            .mouseMoved,
            .cursorUpdate
        ]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
        cursorTrackingArea = trackingArea
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

    override func mouseEntered(with event: NSEvent) {
        syncResizeCursor(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        syncResizeCursor(with: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        syncResizeCursor(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        syncResizeCursor(with: event)
    }
}

private struct MirrorContentView: View {
    let sessionManager: CameraSessionManager

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                content
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color.clear)
            .clipShape(Circle())
            .contentShape(Circle())
        }
        .onAppear {
            sessionManager.start()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch sessionManager.state {
        case .unauthorized:
            CameraPermissionDeniedView(sessionManager: sessionManager)
        case let .failed(message):
            placeholder(text: message)
        default:
            CameraPreviewView(sessionManager: sessionManager, isMirrored: sessionManager.isMirrored)
        }
    }

    private func placeholder(text: String) -> some View {
        ZStack {
            Color.black.opacity(0.88)
            Text(text)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(24)
        }
    }
}

/// 摄像头权限被拒后的降级态：说明缺了什么、怎么补，并支持直接跳系统设置。
/// 系统提醒弹窗只出现一次，被拒后必须从这里给用户一条出口。
private struct CameraPermissionDeniedView: View {
    let sessionManager: CameraSessionManager
    @FocusState private var isSettingsButtonFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.88)
            VStack(spacing: 12) {
                Text("未获得摄像头权限")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("在系统设置里允许摄像头访问后，镜子才能显示画面")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)

                Button(action: openCameraSettings) {
                    Text("打开系统设置")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(isSettingsButtonFocused ? 0.34 : 0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(isSettingsButtonFocused ? Color.white : Color.clear, lineWidth: 2)
                )
                // 去掉系统默认的蓝色焦点框，改用上面的自绘焦点态，保证键盘导航依然可见。
                .focusEffectDisabled()
                .focused($isSettingsButtonFocused)
                .accessibilityLabel("打开摄像头设置")
                .accessibilityHint("在系统设置中允许 Mirror 使用摄像头。")
            }
            .padding(24)
        }
        .onAppear {
            sessionManager.recheckAuthorization()
        }
        // 菜单栏应用经常收不到 didBecomeActive；悬浮窗也常一直可见，不会再走 onAppear。
        // 降级态可见期间轮询系统授权，用户在系统设置里打开开关后无需再点镜子。
        .task {
            while !Task.isCancelled {
                sessionManager.recheckAuthorization()
                try? await Task.sleep(for: .milliseconds(800))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            sessionManager.recheckAuthorization()
        }
    }

    private func openCameraSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Camera",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera",
            "x-apple.systempreferences:com.apple.preference.security"
        ]
        for string in urls {
            guard let url = URL(string: string) else {
                continue
            }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}

extension NSWindow {
    func adjustMirrorOpacity(with event: NSEvent) {
        let stepScale = event.hasPreciseScrollingDeltas ? (0.01 / 3.0) : (0.08 / 3.0)
        let nextAlpha = alphaValue + (event.scrollingDeltaY * stepScale)
        alphaValue = min(max(nextAlpha, 0.1), 1.0)
        UserDefaults.standard.set(alphaValue, forKey: MirrorPersistenceKey.alpha)
    }

    func resizeMirror(using event: NSEvent, state: inout MirrorResizeState) {
        let currentVector = vector(from: state.centerInScreen, to: NSEvent.mouseLocation)
        let projectedDistance = projectedLength(of: currentVector, onto: state.resizeAxis)
        let delta = projectedDistance - state.referenceProjectedDistance
        let unclampedSize = state.referenceSize + (delta * 2.0)
        let targetSize = alignedToBacking(min(max(unclampedSize, MirrorResizeState.minSize), MirrorResizeState.maxSize))
        let didHitLimit = unclampedSize < MirrorResizeState.minSize || unclampedSize > MirrorResizeState.maxSize

        let newOrigin = NSPoint(
            x: alignedToBacking(state.centerInScreen.x - (targetSize / 2.0)),
            y: alignedToBacking(state.centerInScreen.y - (targetSize / 2.0))
        )

        if frame.width != targetSize || frame.origin != newOrigin {
            setFrame(NSRect(origin: newOrigin, size: NSSize(width: targetSize, height: targetSize)), display: false)
        }

        if !didHitLimit || targetSize != state.referenceSize {
            state.referenceSize = targetSize
            state.referenceProjectedDistance = projectedDistance
        }
    }

    private func alignedToBacking(_ value: CGFloat) -> CGFloat {
        let scale = max(backingScaleFactor, 1.0)
        return (value * scale).rounded() / scale
    }
}

@MainActor
struct MirrorResizeState {
    static let minSize: CGFloat = 160
    static let maxSize: CGFloat = 520

    var referenceSize: CGFloat
    let centerInScreen: CGPoint
    let resizeAxis: CGVector
    var referenceProjectedDistance: CGFloat
    let cursor: NSCursor
}

private enum MirrorResizeHandle {
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
    case topLeft
}

@MainActor
private enum MirrorResizeCursors {
    static func cursor(for handle: MirrorResizeHandle) -> NSCursor {
        return switch handle {
        case .top, .bottom:
            vertical
        case .left, .right:
            horizontal
        case .topRight, .bottomLeft:
            diagonalNESW
        case .topLeft, .bottomRight:
            diagonalNWSE
        }
    }

    private static let vertical = makeResizeCursor(from: NSPoint(x: 12, y: 4), to: NSPoint(x: 12, y: 20))
    private static let horizontal = makeResizeCursor(from: NSPoint(x: 4, y: 12), to: NSPoint(x: 20, y: 12))
    private static let diagonalNESW = makeResizeCursor(from: NSPoint(x: 6, y: 6), to: NSPoint(x: 18, y: 18))
    private static let diagonalNWSE = makeResizeCursor(from: NSPoint(x: 6, y: 18), to: NSPoint(x: 18, y: 6))

    private static func makeResizeCursor(from start: NSPoint, to end: NSPoint) -> NSCursor {
        let size = NSSize(width: 24, height: 24)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        drawResizeArrow(from: start, to: end, color: .white, lineWidth: 4.0)
        drawResizeArrow(from: start, to: end, color: .black, lineWidth: 2.0)

        return NSCursor(image: image, hotSpot: NSPoint(x: size.width / 2, y: size.height / 2))
    }

    private static func drawResizeArrow(from start: NSPoint, to end: NSPoint, color: NSColor, lineWidth: CGFloat) {
        let shaft = NSBezierPath()
        shaft.lineWidth = lineWidth
        shaft.lineCapStyle = .round
        shaft.move(to: start)
        shaft.line(to: end)
        color.setStroke()
        shaft.stroke()

        drawArrowHead(tip: start, toward: end, color: color, lineWidth: lineWidth)
        drawArrowHead(tip: end, toward: start, color: color, lineWidth: lineWidth)
    }

    private static func drawArrowHead(tip: NSPoint, toward anchor: NSPoint, color: NSColor, lineWidth: CGFloat) {
        let dx = anchor.x - tip.x
        let dy = anchor.y - tip.y
        let length = hypot(dx, dy)
        guard length > 0 else {
            return
        }

        let ux = dx / length
        let uy = dy / length
        let headLength: CGFloat = 5.0
        let spread: CGFloat = 3.0
        let baseX = tip.x + (ux * headLength)
        let baseY = tip.y + (uy * headLength)
        let px = -uy
        let py = ux

        let left = NSPoint(x: baseX + (px * spread), y: baseY + (py * spread))
        let right = NSPoint(x: baseX - (px * spread), y: baseY - (py * spread))

        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.move(to: tip)
        path.line(to: left)
        path.move(to: tip)
        path.line(to: right)
        color.setStroke()
        path.stroke()
    }
}

func beginResizeIfNeeded(with event: NSEvent, in view: NSView) -> MirrorResizeState? {
    guard
        let window = view.window,
        let localPoint = view.resizeHitPoint(for: event),
        view.isInResizeRing(localPoint)
    else {
        return nil
    }

    let centerInScreen = CGPoint(x: window.frame.midX, y: window.frame.midY)
    let initialVector = vector(from: centerInScreen, to: NSEvent.mouseLocation)
    let resizeAxis = normalized(initialVector) ?? unitVector(for: view.resizeHandle(at: localPoint))
    return MirrorResizeState(
        referenceSize: window.frame.width,
        centerInScreen: centerInScreen,
        resizeAxis: resizeAxis,
        referenceProjectedDistance: projectedLength(of: initialVector, onto: resizeAxis),
        cursor: view.resizeCursor(at: localPoint) ?? NSCursor.arrow
    )
}

func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
    hypot(lhs.x - rhs.x, lhs.y - rhs.y)
}

func vector(from lhs: CGPoint, to rhs: CGPoint) -> CGVector {
    CGVector(dx: rhs.x - lhs.x, dy: rhs.y - lhs.y)
}

func normalized(_ vector: CGVector) -> CGVector? {
    let length = hypot(vector.dx, vector.dy)
    guard length > 0 else {
        return nil
    }

    return CGVector(dx: vector.dx / length, dy: vector.dy / length)
}

func projectedLength(of vector: CGVector, onto axis: CGVector) -> CGFloat {
    (vector.dx * axis.dx) + (vector.dy * axis.dy)
}

private func unitVector(for handle: MirrorResizeHandle) -> CGVector {
    let diagonal: CGFloat = 0.7071067811865476

    switch handle {
    case .top:
        return CGVector(dx: 0, dy: 1)
    case .topRight:
        return CGVector(dx: diagonal, dy: diagonal)
    case .right:
        return CGVector(dx: 1, dy: 0)
    case .bottomRight:
        return CGVector(dx: diagonal, dy: -diagonal)
    case .bottom:
        return CGVector(dx: 0, dy: -1)
    case .bottomLeft:
        return CGVector(dx: -diagonal, dy: -diagonal)
    case .left:
        return CGVector(dx: -1, dy: 0)
    case .topLeft:
        return CGVector(dx: -diagonal, dy: diagonal)
    }
}

func restoredMirrorOpacity() -> CGFloat {
    let defaults = UserDefaults.standard
    guard defaults.object(forKey: MirrorPersistenceKey.alpha) != nil else {
        return 1.0
    }

    let alpha = defaults.double(forKey: MirrorPersistenceKey.alpha)
    return min(max(alpha, 0.1), 1.0)
}

extension NSView {
    func makeResizeStateIfNeeded(with event: NSEvent) -> MirrorResizeState? {
        beginResizeIfNeeded(with: event, in: self)
    }

    func resizeHitPoint(for event: NSEvent) -> CGPoint? {
        guard window != nil else {
            return nil
        }

        return convert(event.locationInWindow, from: nil)
    }

    func syncResizeCursor(with event: NSEvent) {
        if let activeResizeCursor = (window as? MirrorPanel)?.activeResizeCursor {
            activeResizeCursor.set()
            return
        }

        guard let point = resizeHitPoint(for: event), let cursor = resizeCursor(at: point) else {
            NSCursor.arrow.set()
            return
        }

        cursor.set()
    }

    func syncResizeCursor(_ cursor: NSCursor) {
        cursor.set()
    }

    func resizeCursor(at point: CGPoint) -> NSCursor? {
        guard isInResizeRing(point) else {
            return nil
        }

        return MirrorResizeCursors.cursor(for: resizeHandle(at: point))
    }

    func isInResizeRing(_ point: CGPoint) -> Bool {
        let radius = min(bounds.width, bounds.height) / 2.0
        let edgeWidth = min(max(bounds.width * 0.12, 18), 32)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let distanceToCenter = distance(from: point, to: center)

        return distanceToCenter <= radius && distanceToCenter >= (radius - edgeWidth)
    }

    fileprivate func resizeHandle(at point: CGPoint) -> MirrorResizeHandle {
        let normalizedPoint = resizeAnglePoint(for: point)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let degrees = positiveDegrees(for: atan2(normalizedPoint.y - center.y, normalizedPoint.x - center.x))

        switch degrees {
        case 22.5..<67.5:
            return .topRight
        case 67.5..<112.5:
            return .top
        case 112.5..<157.5:
            return .topLeft
        case 157.5..<202.5:
            return .left
        case 202.5..<247.5:
            return .bottomLeft
        case 247.5..<292.5:
            return .bottom
        case 292.5..<337.5:
            return .bottomRight
        default:
            return .right
        }
    }

    private func positiveDegrees(for radians: CGFloat) -> CGFloat {
        let degrees = radians * 180.0 / .pi
        return degrees >= 0 ? degrees : degrees + 360.0
    }

    private func resizeAnglePoint(for point: CGPoint) -> CGPoint {
        guard isFlipped else {
            return point
        }

        return CGPoint(x: point.x, y: bounds.height - point.y)
    }
}
