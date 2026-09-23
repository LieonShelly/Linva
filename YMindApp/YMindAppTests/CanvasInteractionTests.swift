import AppKit
import CoreGraphics
import Testing
@testable import YMindApp

@Suite("画布交互")
struct CanvasInteractionTests {
    @Test func dragPanState_nodePress_neverPansUntilMouseUp() {
        var state = CanvasDragPanState()
        state.begin(at: CGPoint(x: 10, y: 10), onNode: true)

        #expect(state.drag(to: CGPoint(x: 20, y: 20)) == nil)
        #expect(state.drag(to: CGPoint(x: 30, y: 30)) == nil)

        state.end()
        state.begin(at: CGPoint(x: 0, y: 0), onNode: false)

        #expect(state.drag(to: CGPoint(x: 5, y: 0)) == CGSize(width: 5, height: 0))
        #expect(state.drag(to: CGPoint(x: 10, y: 5)) == CGSize(width: 5, height: 5))
    }

    @Test @MainActor func canvasMTKView_restoreFocus_becomesFirstResponder() {
        let session = DocumentSession()
        let canvas = CanvasMTKView(
            frame: NSRect(x: 0, y: 0, width: 400, height: 300),
            device: nil,
            renderer: nil,
            session: session,
            onSelect: { _ in },
            onEdit: { _ in },
            onAddChild: {},
            onAddSibling: {},
            onDelete: {}
        )
        let window = NSWindow(
            contentRect: canvas.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = canvas
        window.makeKeyAndOrderFront(nil)

        let focusStealer = FocusStealerView(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        canvas.addSubview(focusStealer)
        window.makeFirstResponder(focusStealer)
        #expect(window.firstResponder === focusStealer)

        canvas.restoreKeyboardFocusIfNeeded(request: 1)
        #expect(window.firstResponder === canvas)

        canvas.restoreKeyboardFocusIfNeeded(request: 1)
        #expect(window.firstResponder === canvas)
    }
}

private final class FocusStealerView: NSView {
    override var acceptsFirstResponder: Bool { true }
}
