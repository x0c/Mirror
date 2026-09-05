import AppKit

/// 镜像窗拖拽 / 外环缩放 / 滚轮透明度：预览层与 SwiftUI 宿主共用同一套事件处理。
@MainActor
enum MirrorWindowGestures {
    static func mouseDown(
        with event: NSEvent,
        in view: NSView,
        resizeState: inout MirrorResizeState?
    ) {
        if event.clickCount == 2 {
            (view.window?.windowController as? MirrorWindowController)?.hideMirror()
            return
        }

        if let state = view.makeResizeStateIfNeeded(with: event) {
            resizeState = state
            (view.window?.windowController as? MirrorWindowController)?.beginInteractiveResize()
            (view.window as? MirrorPanel)?.activeResizeCursor = state.cursor
            view.syncResizeCursor(state.cursor)
            return
        }

        view.window?.performDrag(with: event)
    }

    static func mouseDragged(
        with event: NSEvent,
        in view: NSView,
        resizeState: inout MirrorResizeState?
    ) {
        guard var state = resizeState, let window = view.window else {
            return
        }

        view.syncResizeCursor(state.cursor)
        window.resizeMirror(using: event, state: &state)
        resizeState = state
    }

    static func finishMouseUp(
        with event: NSEvent,
        in view: NSView,
        resizeState: inout MirrorResizeState?
    ) {
        let didResize = resizeState != nil
        resizeState = nil
        if didResize {
            (view.window?.windowController as? MirrorWindowController)?.endInteractiveResize()
        }
        (view.window as? MirrorPanel)?.activeResizeCursor = nil
        view.syncResizeCursor(with: event)
    }

    static func scrollWheel(with event: NSEvent, in view: NSView) {
        view.window?.adjustMirrorOpacity(with: event)
    }
}
