import AppKit
import MetalKit
import SwiftUI

struct CanvasMetalView: NSViewRepresentable {
    @ObservedObject var session: DocumentSession

    func makeNSView(context: Context) -> CanvasMTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            session.errorMessage = "无法初始化 Metal"
            return CanvasMTKView(frame: .zero, device: nil, renderer: nil, session: session)
        }

        do {
            let renderer = try MetalRenderer(device: device)
            return CanvasMTKView(
                frame: .zero,
                device: device,
                renderer: renderer,
                session: session
            )
        } catch {
            session.errorMessage = "无法初始化 Metal：\(error.localizedDescription)"
            return CanvasMTKView(frame: .zero, device: device, renderer: nil, session: session)
        }
    }

    func updateNSView(_ view: CanvasMTKView, context: Context) {
        view.session = session
        view.fitContentIfNeeded(force: session.camera == Camera())
        view.setNeedsDisplay(view.bounds)
    }
}

final class CanvasMTKView: MTKView, MTKViewDelegate {
    var session: DocumentSession

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private let renderer: MetalRenderer?
    private var lastDragPoint: CGPoint?
    private var didFitContent = false

    init(
        frame: CGRect,
        device: MTLDevice?,
        renderer: MetalRenderer?,
        session: DocumentSession
    ) {
        self.renderer = renderer
        self.session = session
        super.init(frame: frame, device: device)

        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        enableSetNeedsDisplay = true
        isPaused = true
        preferredFramesPerSecond = 60
        clearColor = MTLClearColorMake(0, 0, 0, 1)
        delegate = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override func layout() {
        super.layout()
        fitContentIfNeeded()
        setNeedsDisplay(bounds)
    }

    func fitContentIfNeeded(force: Bool = false) {
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }
        if force {
            didFitContent = false
        }
        guard !didFitContent else {
            return
        }

        let contentBounds = session.snapshot.frames.values.reduce(CGRect.null) {
            $0.union($1.rect)
        }
        var camera = session.camera
        camera.fit(contentBounds: contentBounds, viewport: bounds.size)
        session.camera = camera
        didFitContent = true
    }

    func draw(in view: MTKView) {
        renderer?.draw(
            in: view,
            snapshot: session.snapshot,
            camera: session.camera,
            selectedId: session.model.selectedId
        )
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        guard size.width > 0, size.height > 0 else {
            return
        }
        view.setNeedsDisplay(view.bounds)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        lastDragPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let lastDragPoint else {
            self.lastDragPoint = point
            return
        }

        session.camera.translation.x += point.x - lastDragPoint.x
        session.camera.translation.y += point.y - lastDragPoint.y
        self.lastDragPoint = point
        setNeedsDisplay(bounds)
    }

    override func mouseUp(with event: NSEvent) {
        lastDragPoint = nil
    }

    override func scrollWheel(with event: NSEvent) {
        let anchor = convert(event.locationInWindow, from: nil)
        let worldAnchor = session.camera.screenToWorld(anchor)
        let sensitivity: CGFloat = event.hasPreciseScrollingDeltas ? 0.012 : 0.08
        let zoom = exp(-event.scrollingDeltaY * sensitivity)
        let newScale = min(max(session.camera.scale * zoom, 0.2), 4)

        session.camera.scale = newScale
        session.camera.translation = CGPoint(
            x: anchor.x - worldAnchor.x * newScale,
            y: anchor.y - worldAnchor.y * newScale
        )
        setNeedsDisplay(bounds)
    }
}
