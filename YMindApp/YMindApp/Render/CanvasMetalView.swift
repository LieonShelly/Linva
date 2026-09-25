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

struct CanvasDragPanState: Equatable {
    private(set) var lastDragPoint: CGPoint?
    private(set) var suppressUntilMouseUp = false

    mutating func begin(at point: CGPoint, onNode: Bool) {
        suppressUntilMouseUp = onNode
        lastDragPoint = onNode ? nil : point
    }

    mutating func drag(to point: CGPoint) -> CGSize? {
        guard !suppressUntilMouseUp else {
            return nil
        }
        guard let lastDragPoint else {
            self.lastDragPoint = point
            return nil
        }
        let delta = CGSize(
            width: point.x - lastDragPoint.x,
            height: point.y - lastDragPoint.y
        )
        self.lastDragPoint = point
        return delta
    }

    mutating func end() {
        lastDragPoint = nil
        suppressUntilMouseUp = false
    }
}

struct CanvasMetalView: NSViewRepresentable {
    @ObservedObject var session: DocumentSession
    var focusRequest: Int = 0
    let onSelect: (UUID?) -> Void
    let onEdit: (UUID) -> Void
    let onAddChild: () -> Void
    let onAddSibling: () -> Void
    let onDelete: () -> Void

    func makeNSView(context: Context) -> CanvasMTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            let view = CanvasMTKView(
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
            // 不能在 view update 期间同步写 @Published。
            DispatchQueue.main.async {
                session.errorMessage = "无法初始化 Metal"
            }
            return view
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
            let message = error.localizedDescription
            let view = CanvasMTKView(
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
            DispatchQueue.main.async {
                session.errorMessage = "无法初始化 Metal：\(message)"
            }
            return view
        }
    }

    func updateNSView(_ view: CanvasMTKView, context: Context) {
        view.session = session
        view.onSelect = onSelect
        view.onEdit = onEdit
        view.onAddChild = onAddChild
        view.onAddSibling = onAddSibling
        view.onDelete = onDelete
        // 仅标记需要适应；真正改 camera 延后到 runloop，避免 Publishing changes from within view updates。
        if session.camera == Camera() {
            view.markNeedsFitContent()
        }
        view.scheduleFitContentIfNeeded()
        view.setNeedsDisplay(view.bounds)
        view.restoreKeyboardFocusIfNeeded(request: focusRequest)
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
    private var dragPanState = CanvasDragPanState()
    private var appliedFocusRequest = 0
    private var didFitContent = false
    private var fitContentScheduled = false

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
        scheduleFitContentIfNeeded()
        setNeedsDisplay(bounds)
    }

    func markNeedsFitContent() {
        didFitContent = false
    }

    func scheduleFitContentIfNeeded() {
        guard !didFitContent, !fitContentScheduled else {
            return
        }
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }

        fitContentScheduled = true
        let contentBounds = session.snapshot.frames.values.reduce(CGRect.null) {
            $0.union($1.rect)
        }
        let viewport = bounds.size

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.fitContentScheduled = false
            guard !self.didFitContent else { return }
            guard self.bounds.width > 0, self.bounds.height > 0 else { return }

            var camera = self.session.camera
            camera.fit(contentBounds: contentBounds, viewport: viewport)
            self.session.camera = camera
            self.didFitContent = true
            self.setNeedsDisplay(self.bounds)
        }
    }

    func draw(in view: MTKView) {
        renderer?.draw(
            in: view,
            snapshot: session.snapshot,
            camera: session.camera,
            selectedId: session.primarySelectedId
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
        dragPanState.begin(at: point, onNode: hit != nil)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let delta = dragPanState.drag(to: point) else {
            return
        }

        session.camera.translation.x += delta.width
        session.camera.translation.y += delta.height
        setNeedsDisplay(bounds)
    }

    override func mouseUp(with event: NSEvent) {
        dragPanState.end()
    }

    func restoreKeyboardFocusIfNeeded(request: Int) {
        guard request != appliedFocusRequest else {
            return
        }
        appliedFocusRequest = request
        window?.makeFirstResponder(self)
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
