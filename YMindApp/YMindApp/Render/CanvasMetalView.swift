import AppKit
import MetalKit
import SwiftUI

/// 单击语义：由画布按修饰键判定，壳层只负责落到选中集 API。
enum CanvasSelectIntent: Equatable {
    case replace
    case toggle
    case range
}

/// 画布工具模式：决定空白处左键拖拽的语义（平移模式找回画布中心用）。
enum CanvasTool: Equatable {
    /// 选择/框选：空白左拖 = 框选，单击空白 = 取消选中。
    case select
    /// 手型平移：空白左拖 = 平移画布。
    case pan
}

/// 画布指针手势状态。纯值类型，便于推演与测试。
enum CanvasPointerGesture: Equatable {
    case none
    /// 平移相机：`lastPoint` 为上一次的视图坐标。
    case pan(origin: CGPoint, lastPoint: CGPoint)
    /// 框选：`tracking == false` 表示忽略拖动（编辑态下不框选）。
    case marquee(origin: CGPoint, current: CGPoint, additive: Bool, tracking: Bool)
    /// 节点按下未拖：`movingIds` 为待搬集；松手未拖则收成单选。
    case pendingDrag(origin: CGPoint, nodeId: UUID, movingIds: Set<UUID>)
    /// 搬枝拖拽中：`intent` 为当前合法放置意图（nil=空白/非法）。
    case drag(movingIds: Set<UUID>, intent: DropIntent?, lastPoint: CGPoint)

    var currentDropIntent: DropIntent? {
        if case let .drag(_, intent, _) = self { return intent }
        return nil
    }

    var marqueeScreenRect: CGRect? {
        guard case let .marquee(origin, current, _, tracking) = self, tracking else {
            return nil
        }
        let rect = marqueeRect(from: origin, to: current)
        return isClickLike(rect) ? nil : rect
    }
}

/// 画布 → 壳层的全部回调；默认空实现，便于测试与预览。
struct CanvasActions {
    var select: (UUID?, CanvasSelectIntent) -> Void = { _, _ in }
    var marqueeSelect: (Set<UUID>, Bool) -> Void = { _, _ in }
    var edit: (UUID) -> Void = { _ in }
    var commitEditing: () -> Void = {}
    var toggleCollapse: (UUID) -> Void = { _ in }
    var toggleCollapseSelection: () -> Void = {}
    var selectAll: () -> Void = {}
    var addChild: () -> Void = {}
    var addSibling: () -> Void = {}
    var delete: () -> Void = {}
    var move: ([UUID], UUID) -> Void = { _, _ in }
    var insertSiblings: ([UUID], UUID, BeforeAfter) -> Void = { _, _, _ in }
    var setSide: ([UUID], Side) -> Void = { _, _ in }
    var applyRootSide: ([UUID], Side) -> Void = { _, _ in }
    var copy: () -> Void = {}
    var cut: () -> Void = {}
    var paste: () -> Void = {}
    var cancelCut: () -> Void = {}
    var clearImage: () -> Void = {}
}

struct CanvasMetalView: NSViewRepresentable {
    @ObservedObject var session: DocumentSession
    var focusRequest: Int = 0
    var actions = CanvasActions()

    func makeNSView(context: Context) -> CanvasMTKView {
        let device = MTLCreateSystemDefaultDevice()
        let renderer: MetalRenderer?
        if let device {
            do {
                renderer = try MetalRenderer(device: device)
            } catch {
                renderer = nil
                let message = error.localizedDescription
                // 不能在 view update 期间同步写 @Published。
                DispatchQueue.main.async {
                    session.errorMessage = "无法初始化 Metal：\(message)"
                }
            }
        } else {
            renderer = nil
            DispatchQueue.main.async {
                session.errorMessage = "无法初始化 Metal"
            }
        }

        let view = CanvasMTKView(
            frame: .zero,
            device: device,
            renderer: renderer,
            session: session
        )
        view.actions = actions
        return view
    }

    func updateNSView(_ view: CanvasMTKView, context: Context) {
        view.session = session
        view.actions = actions
        view.refreshCursorForTool()
        // D1：布局变化（工具栏切换/⌘Z/⌘⇧Z）经 session.fitVersion 统一触发一次再适配。
        if session.fitVersion != view.appliedFitVersion {
            view.appliedFitVersion = session.fitVersion
            view.markNeedsFitContent()
        }
        // 仅标记需要适应；真正改 camera 延后到 runloop，避免 Publishing changes from within view updates.
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
    var actions = CanvasActions()
    /// 已消费的 fitVersion；与 session.fitVersion 不一致时由 updateNSView 触发一次再适配。
    var appliedFitVersion = 0

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// 手型平移模式显示手掌光标，模式切换时刷新。
    func refreshCursorForTool() {
        guard appliedCanvasTool != session.canvasTool else { return }
        appliedCanvasTool = session.canvasTool
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if session.canvasTool == .pan {
            addCursorRect(bounds, cursor: .openHand)
        }
    }

    private let renderer: MetalRenderer?
    private var gesture: CanvasPointerGesture = .none
    private var isSpaceHeld = false
    private var appliedFocusRequest = 0
    private var appliedCanvasTool: CanvasTool?
    private var didFitContent = false
    private var fitContentScheduled = false

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

        registerForDraggedTypes([.png, .tiff, .fileURL])
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
            selectedIds: session.selectedIds,
            selectionAnchorId: session.selectionAnchorId,
            selectedImageBlock: session.selectedImageBlock,
            cutSourceIds: session.cutSourceIds,
            intent: gesture.currentDropIntent,
            searchHitId: session.search.currentMatchId,
            marquee: gesture.marqueeScreenRect
        )
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        guard size.width > 0, size.height > 0 else {
            return
        }
        view.setNeedsDisplay(view.bounds)
    }

    // MARK: - 指针

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard event.buttonNumber == 0 else { return }
        beginPointerGesture(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        continuePointerGesture(with: event, point: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        endPointerGesture()
    }

    /// 中键（及其他鼠标键）拖拽始终平移相机。
    override func otherMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        gesture = .pan(origin: point, lastPoint: point)
    }

    override func otherMouseDragged(with event: NSEvent) {
        continuePointerGesture(with: event, point: convert(event.locationInWindow, from: nil))
    }

    override func otherMouseUp(with event: NSEvent) {
        gesture = .none
    }

    private func beginPointerGesture(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let hit = hitTestCanvas(
            screenPoint: point,
            snapshot: session.snapshot,
            camera: session.camera
        )
        let wasEditing = session.editingId != nil

        if wasEditing {
            // 编辑排他：点在编辑节点上不动；点别处先提交编辑。
            if case let .node(id) = hit, id == session.editingId {
                return
            }
            actions.commitEditing()
        }

        switch hit {
        case let .branchToggle(nodeId):
            actions.toggleCollapse(nodeId)
            gesture = .none
        case let .node(id):
            let intent = wasEditing ? .replace : selectIntent(for: event)
            if event.clickCount == 2 {
                if let hit = hitTestImageBlock(
                    screenPoint: point,
                    snapshot: session.snapshot,
                    camera: session.camera
                ) {
                    session.selectImageBlock(nodeId: hit.nodeId, blockId: hit.blockId)
                } else {
                    actions.edit(id)             // 双击文字区 → 进文字编辑（现状）
                }
                gesture = .none
                return
            }
            guard !wasEditing, intent == .replace else {
                actions.select(id, intent)
                gesture = .none
                return
            }
            let isMulti = session.selectedIds.count > 1
            if isMulti, session.selectedIds.contains(id) {
                // 已在多选中：保留多选供拖整组；松手未拖再收成单选。
                let moving = session.model.movableTopLevel(ids: session.selectedIds)
                gesture = .pendingDrag(
                    origin: point,
                    nodeId: id,
                    movingIds: Set(moving)
                )
            } else {
                actions.select(id, .replace)
                gesture = .pendingDrag(origin: point, nodeId: id, movingIds: [id])
            }
        case .empty:
            if isSpaceHeld || session.canvasTool == .pan {
                // 手型平移：空格临时平移，或处于平移模式。
                gesture = .pan(origin: point, lastPoint: point)
            } else {
                // 选择/框选模式：空白左拖 = 框选。
                gesture = .marquee(
                    origin: point,
                    current: point,
                    additive: !wasEditing && isAdditive(event),
                    tracking: !wasEditing
                )
            }
        }
    }

    private func continuePointerGesture(with event: NSEvent, point: CGPoint) {
        switch gesture {
        case .none:
            break
        case let .pan(origin, lastPoint):
            session.camera.translation.x += point.x - lastPoint.x
            session.camera.translation.y += point.y - lastPoint.y
            gesture = .pan(origin: origin, lastPoint: point)
            setNeedsDisplay(bounds)
        case let .marquee(origin, _, additive, tracking):
            guard tracking else { return }
            gesture = .marquee(
                origin: origin,
                current: point,
                additive: additive,
                tracking: true
            )
            setNeedsDisplay(bounds)
        case let .pendingDrag(origin, _, movingIds):
            guard hasExceededDragThreshold(from: origin, to: point) else { return }
            gesture = .drag(
                movingIds: movingIds,
                intent: computeDropIntent(at: point, movingIds: movingIds),
                lastPoint: point
            )
            setNeedsDisplay(bounds)
        case let .drag(movingIds, _, lastPoint):
            let intent = computeDropIntent(at: point, movingIds: movingIds)
            gesture = .drag(movingIds: movingIds, intent: intent, lastPoint: point)
            setNeedsDisplay(bounds)
        }
    }

    private func endPointerGesture() {
        defer { gesture = .none }
        switch gesture {
        case .none, .pan:
            break
        case .pendingDrag(_, let nodeId, _):
            // 未拖出阈值：收成单击单选。
            actions.select(nodeId, .replace)
        case .drag(let movingIds, let intent, _):
            if let intent {
                let ids = Array(movingIds)
                switch intent {
                case .child(let targetId):
                    actions.move(ids, targetId)
                case .before(let anchorId):
                    actions.insertSiblings(ids, anchorId, .before)
                case .after(let anchorId):
                    actions.insertSiblings(ids, anchorId, .after)
                case .sideLeft(_, let viaEmpty):
                    if viaEmpty { actions.setSide(ids, .left) }
                    else { actions.applyRootSide(ids, .left) }
                case .sideRight(_, let viaEmpty):
                    if viaEmpty { actions.setSide(ids, .right) }
                    else { actions.applyRootSide(ids, .right) }
                }
            }
            // intent == nil：取消搬移，树不变。
        case .marquee(let origin, let current, let additive, let tracking):
            let rect = marqueeRect(from: origin, to: current)
            if !tracking || isClickLike(rect) {
                // 几乎没拖动：视为点空白取消选中（追加模式不强制清空）。
                if !additive {
                    actions.select(nil, .replace)
                }
                return
            }
            let ids = marqueeIntersectingIds(
                worldRect: worldRect(fromScreenRect: rect, camera: session.camera),
                snapshot: session.snapshot
            )
            actions.marqueeSelect(ids, additive)
        }
        // 手势复位（defer）后放置高亮消失，主动重绘一次，不依赖 SwiftUI 间接链路。
        setNeedsDisplay(bounds)
    }

    private func computeDropIntent(at point: CGPoint, movingIds: Set<UUID>) -> DropIntent? {
        resolveDropIntent(
            screenPoint: point,
            movingIds: movingIds,
            snapshot: session.snapshot,
            camera: session.camera,
            model: session.model
        )
    }

    private func selectIntent(for event: NSEvent) -> CanvasSelectIntent {
        let flags = event.modifierFlags
        if flags.contains(.command) || flags.contains(.control) {
            return .toggle
        }
        if flags.contains(.shift) {
            return .range
        }
        return .replace
    }

    private func isAdditive(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        return flags.contains(.command) || flags.contains(.control)
    }

    // MARK: - 键盘

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 {
            // 空格按住 = 平移修饰键；吞掉以免系统响铃。
            if !event.isARepeat, session.editingId == nil {
                isSpaceHeld = true
            }
            return
        }

        // 编辑排他：编辑浮层获得焦点时不抢快捷键。
        guard session.editingId == nil else {
            super.keyDown(with: event)
            return
        }

        let flags = event.modifierFlags
        if flags.contains(.command),
           let key = event.charactersIgnoringModifiers?.lowercased() {
            switch key {
            case "c": actions.copy(); return
            case "x": actions.cut(); return
            case "v": actions.paste(); return
            case "a": actions.selectAll(); return
            case ".": actions.toggleCollapseSelection(); return
            default: break
            }
        }

        switch event.keyCode {
        case 48:
            actions.addChild()
        case 36, 76:
            actions.addSibling()
        case 51, 117:
            if session.selectedImageBlock != nil {
                actions.clearImage()      // 选中图片块 → 删块
            } else {
                actions.delete()          // 删节点
            }
        case 53:
            if session.selectedImageBlock != nil {
                session.clearImageSelection()   // Esc 先退图片选中
            } else if !session.cutSourceIds.isEmpty {
                actions.cancelCut()
            } else {
                actions.select(nil, .replace)
            }
        case 44:
            actions.toggleCollapseSelection()
        default:
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            isSpaceHeld = false
            return
        }
        super.keyUp(with: event)
    }

    override func resignFirstResponder() -> Bool {
        isSpaceHeld = false
        return super.resignFirstResponder()
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

    // MARK: - 图片拖入（FR-G2；独立于搬枝 DropIntent）

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        hasDraggableImage(sender) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let data = draggedImageData(sender) else { return false }
        let point = convert(sender.draggingLocation, from: nil)
        // 落点节点即为目标：先选中再贴图（未选中节点也能拖入该节点）
        guard let nodeId = hitTestNode(
            screenPoint: point,
            snapshot: session.snapshot,
            camera: session.camera
        ) else { return false }
        session.selectOnly(nodeId)
        if !session.appendPastedImage(from: data) {
            DispatchQueue.main.async { self.session.errorMessage = "无法读取图片" }
        }
        return true
    }

    private func hasDraggableImage(_ sender: NSDraggingInfo) -> Bool {
        draggedImageData(sender) != nil
    }

    private func draggedImageData(_ sender: NSDraggingInfo) -> Data? {
        let pb = sender.draggingPasteboard
        if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff) {
            return data
        }
        for url in (pb.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? [] {
            let ext = url.pathExtension.lowercased()
            if ["png", "jpeg", "jpg", "gif", "tiff", "heic"].contains(ext),
               let data = try? Data(contentsOf: url) {
                return data
            }
        }
        return nil
    }
}
