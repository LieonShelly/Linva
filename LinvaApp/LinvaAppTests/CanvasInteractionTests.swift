import AppKit
import CoreGraphics
import Testing
@testable import LinvaApp

@Suite("画布交互")
struct CanvasInteractionTests {
    @Test func marqueeRect_normalizesAnyDragDirection() {
        let reversed = marqueeRect(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 4, y: 5))
        let forward = marqueeRect(from: CGPoint(x: 4, y: 5), to: CGPoint(x: 10, y: 20))

        #expect(reversed == forward)
        #expect(forward == CGRect(x: 4, y: 5, width: 6, height: 15))
    }

    @Test func hasExceededDragThreshold_crossesAtFourPoints() {
        let origin = CGPoint(x: 100, y: 100)
        #expect(!hasExceededDragThreshold(from: origin, to: CGPoint(x: 103, y: 101)))
        #expect(hasExceededDragThreshold(from: origin, to: CGPoint(x: 105, y: 100)))
        #expect(hasExceededDragThreshold(from: origin, to: CGPoint(x: 100, y: 96)))
    }

    @Test func pointerGesture_drawsMarqueeOnlyWhenTrackingAndPastThreshold() {
        let clickLike = CanvasPointerGesture.marquee(
            origin: CGPoint(x: 10, y: 10),
            current: CGPoint(x: 13, y: 12),
            additive: false,
            tracking: true
        )
        #expect(clickLike.marqueeScreenRect == nil)

        let dragging = CanvasPointerGesture.marquee(
            origin: CGPoint(x: 10, y: 10),
            current: CGPoint(x: 40, y: 30),
            additive: false,
            tracking: true
        )
        #expect(dragging.marqueeScreenRect == CGRect(x: 10, y: 10, width: 30, height: 20))

        // 编辑态：只记起点不框选。
        let untracked = CanvasPointerGesture.marquee(
            origin: CGPoint(x: 10, y: 10),
            current: CGPoint(x: 40, y: 30),
            additive: false,
            tracking: false
        )
        #expect(untracked.marqueeScreenRect == nil)
        #expect(CanvasPointerGesture.pan(origin: .zero, lastPoint: .zero).marqueeScreenRect == nil)
        #expect(CanvasPointerGesture.none.marqueeScreenRect == nil)
    }

    @Test func worldRect_undoesCameraTransform() {
        let camera = Camera(translation: CGPoint(x: 100, y: 80), scale: 2)

        let world = worldRect(
            fromScreenRect: CGRect(x: 120, y: 100, width: 40, height: 20),
            camera: camera
        )

        #expect(world == CGRect(x: 10, y: 10, width: 20, height: 10))
    }

    @Test @MainActor func canvasMTKView_restoreFocus_becomesFirstResponder() {
        let session = DocumentSession()
        let canvas = CanvasMTKView(
            frame: NSRect(x: 0, y: 0, width: 400, height: 300),
            device: nil,
            renderer: nil,
            session: session
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
