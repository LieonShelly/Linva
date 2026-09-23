import AppKit
import MetalKit
import SwiftUI

func hitTest(
    screenPoint: CGPoint,
    snapshot: LayoutSnapshot,
    camera: Camera
) -> UUID? {
    hitTestNode(screenPoint: screenPoint, snapshot: snapshot, camera: camera)
}

private func hitTestNode(
    screenPoint: CGPoint,
    snapshot: LayoutSnapshot,
    camera: Camera
) -> UUID? {
    let worldPoint = camera.screenToWorld(screenPoint)
    return snapshot.frames.values
        .filter { $0.rect.contains(worldPoint) }
        .min {
            $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height
        }?
        .id
}

struct CanvasMetalView: NSViewRepresentable {
    @ObservedObject var session: DocumentSession
    let onSelect: (UUID?) -> Void
    let onEdit: (UUID) -> Void
    let onAddChild: () -> Void
    let onAddSibling: () -> Void
    let onDelete: () -> Void

    func makeNSView(context: Context) -> CanvasMTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            session.errorMessage = "无法初始化 Metal"
            return CanvasMTKView(
                frame: .zero,
                device: nil,
                renderer: nil,
                session: session,
                onSelect: onSelect,
                onEdit: onEdit,
                onAddChild: onAddChild,
                onAddSibling: onAddSibling,
                onDelete: onDelete
            )
        }

        do {
            let renderer = try MetalRenderer(device: device)
            return CanvasMTKView(
                frame: .zero,
                device: device,
                renderer: renderer,
                session: session,
                onSelect: onSelect,
                onEdit: onEdit,
                onAddChild: onAddChild,
                onAddSibling: onAddSibling,
                onDelete: onDelete
            )
        } catch {
            session.errorMessage = "无法初始化 Metal：\(error.localizedDescription)"
            return CanvasMTKView(
                frame: .zero,
                device: device,
                renderer: nil,
                session: session,
                onSelect: onSelect,
                onEdit: onEdit,
                onAddChild: onAddChild,
                onAddSibling: onAddSibling,
                onDelete: onDelete
            )
        }
    }

    func updateNSView(_ view: CanvasMTKView, context: Context) {
        view.session = session
        view.onSelect = onSelect
        view.onEdit = onEdit
        view.onAddChild = onAddChild
        view.onAddSibling = onAddSibling
        view.onDelete = onDelete
        view.fitContentIfNeeded(force: session.camera == Camera())
        view.setNeedsDisplay(view.bounds)
    }
}

final class CanvasMTKView: MTKView, MTKViewDelegate {
    var session: DocumentSession
    var onSelect: (UUID?) -> Void
    var onEdit: (UUID) -> Void
    var onAddChild: () -> Void
    var onAddSibling: () -> Void
    var onDelete: () -> Void

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private let renderer: MetalRenderer?
    private var lastDragPoint: CGPoint?
    private var didFitContent = false

    init(
        frame: CGRect,
        device: MTLDevice?,
        renderer: MetalRenderer?,
        session: DocumentSession,
        onSelect: @escaping (UUID?) -> Void,
        onEdit: @escaping (UUID) -> Void,
        onAddChild: @escaping () -> Void,
        onAddSibling: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.renderer = renderer
        self.session = session
        self.onSelect = onSelect
        self.onEdit = onEdit
        self.onAddChild = onAddChild
        self.onAddSibling = onAddSibling
        self.onDelete = onDelete
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
            selectedId: session.selectedId
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
        let point = convert(event.locationInWindow, from: nil)
        let hit = hitTestNode(
            screenPoint: point,
            snapshot: session.snapshot,
            camera: session.camera
        )
        onSelect(hit)
        if let hit, event.clickCount == 2 {
            onEdit(hit)
        }
        lastDragPoint = hit == nil ? point : nil
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

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 48:
            onAddChild()
        case 36, 76:
            onAddSibling()
        case 51, 117:
            onDelete()
        default:
            super.keyDown(with: event)
        }
    }
}
