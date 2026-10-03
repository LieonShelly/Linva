import Combine
import CoreGraphics
import Foundation

enum DocumentSessionError: Error, Equatable {
    case noFileURL
}

/// 待恢复会话提示（Task 3 启动扫描生成；本阶段仅声明态）。
struct RecoveryOffer: Equatable {
    let meta: AutosaveMeta
}

final class DocumentSession: ObservableObject {
    let model: MindMapModel
    let commandBus: CommandBus

    @Published var fileURL: URL?
    @Published var isDirty = false
    @Published private(set) var undoRevision = 0
    /// 相机：普通属性，不 @Published —— 手势（平移/缩放）每帧写入不发布，避免 SwiftUI
    /// 观察者（ContentView @ObservedObject）每帧重求值 body → 工具栏反复重布局（性能 R5）。
    /// 画布渲染直接读本属性；非手势相机写入经 commitCamera() 发布一次低频已提交信号。
    var camera = Camera()
    /// 相机"已提交"版本号（非手势相机变化：工具栏缩放/适应/加载/居中）。CanvasMTKView
    /// 订阅它触发重绘；commitCamera 同时同步 zoomPercent。
    @Published private(set) var cameraCommittedRevision = 0
    /// 工具栏缩放百分比镜像（性能 R5）：仅在相机"提交"边界由 syncZoomPercent() 更新，
    /// 避免每帧相机发布驱动 SwiftUI 工具栏重布局。
    @Published private(set) var zoomPercent = 100
    @Published var canvasTool: CanvasTool = .select
    @Published var snapshot: LayoutSnapshot
    @Published private(set) var selectedIds: Set<UUID> = []
    @Published private(set) var selectionAnchorId: UUID?
    @Published private(set) var editingId: UUID?
    @Published var draftText = ""
    @Published var errorMessage: String?
    @Published private(set) var clipboard: ClipboardPayload?
    @Published private(set) var cutSourceIds: Set<UUID> = []
    /// 图片块级选中（节点内子元素）；不入命令栈，同时最多一个。
    @Published private(set) var selectedImageBlock: (nodeId: UUID, blockId: UUID)?
    /// 图片归一注入点（App 组合根赋 ImageNormalizer.normalize；测试注入 stub）。Session 白名单无 ImageIO。
    var imageNormalizer: ((Data) -> (data: Data, pixelSize: ImagePixelSize)?)?
    @Published var importPreview: ImportPreviewState?
    /// 自动保存/恢复配对用（未命名文档亦然）。导入 plan 已引入，勿重复声明。
    var documentID = UUID()
    /// 启动扫描待恢复会话提示（Task 3 填充；newDocument/load 时清空）。
    @Published var recovery: RecoveryOffer?

    /// 布局变化触发画布重新 fit 的信号（D1：切换/撤销均经 markDirtyAndRelayout 统一 bump）。
    @Published private(set) var fitVersion = 0
    private var appliedLayoutForFit: LayoutKind?

    private let layoutPipeline: LayoutPipeline
    private let persistence: DocumentPersistence
    private let editingController: EditingController

    var primarySelectedId: UUID? { model.primarySelectedId }

    var windowTitle: String {
        fileURL?.lastPathComponent ?? "未命名"
    }

    init(
        model: MindMapModel? = nil,
        layoutPipeline: LayoutPipeline = LayoutPipeline(),
        autosaveStore: AutosaveStore = AutosaveStore(),
        securityScopedAccess: SecurityScopedAccess = SecurityScopedAccess()
    ) {
        let model = model ?? MindMapModel.makeNew()
        self.model = model
        self.commandBus = CommandBus(model: model)
        self.layoutPipeline = layoutPipeline
        self.persistence = DocumentPersistence(
            backend: YMindFilePersistence(),
            securityScopedAccess: securityScopedAccess,
            autosaveStore: autosaveStore
        )
        // 采纳初始文档为 lastSaved：保持「未改动的初始文档即 clean」语义
        // （`commandChanges_refreshUndoState_andReturnToCleanSnapshot` 与真实会话依赖）。
        self.persistence.adopt(
            document: model.document,
            fileURL: nil,
            isDirty: false,
            keepLastSaved: false,
            regenerateID: false,
            clearRecovery: false
        )
        self.editingController = EditingController(model: model, commandBus: commandBus)
        self.snapshot = LayoutSnapshot(frames: [:], edges: [])
        self.selectedIds = model.selectedIds
        self.selectionAnchorId = model.selectionAnchorId
        self.fileURL = nil
        self.isDirty = false
        self.documentID = persistence.documentID
        wireCommandBus()
        relayout()
        appliedLayoutForFit = model.document.layout
    }

    func newDocument() {
        commitEditingIfNeeded()
        let doc = MindMapDocument.blank()
        model.document = doc
        persistence.adopt(document: doc, fileURL: nil, isDirty: false,
                          keepLastSaved: false, regenerateID: true)
        resetSessionState(selecting: doc.root.id)
    }

    /// 载入一次导入解析出的新树为当前文档：等同「打开」语义但 fileURL=nil、isDirty=true。
    func loadImported(_ document: MindMapDocument) {
        commitEditingIfNeeded()
        model.document = document
        // keepLastSaved: true —— 导入文档无磁盘文件，撤销回载入态 isDirty 仍 true。
        persistence.adopt(document: document, fileURL: nil, isDirty: true,
                          keepLastSaved: true, regenerateID: true)
        resetSessionState(selecting: document.root.id)
    }

    func cancelImport() {
        importPreview = nil
        errorMessage = nil
    }

    // MARK: - 自动保存恢复

    /// 启动扫描：若存在未保存副本，返回「最新一份」的 offer；否则 nil。
    @discardableResult
    func scanForRecovery() -> RecoveryOffer? {
        let offer = persistence.scanForRecovery()
        recovery = persistence.recovery
        return offer
    }

    /// 「恢复更改」：载入副本为当前文档，标记未保存，删除该副本。
    func restore(draftFrom offer: RecoveryOffer) throws {
        let doc = try persistence.restore(draftFrom: offer)
        commitEditingIfNeeded()
        model.document = doc
        persistence.adopt(
            document: doc,
            fileURL: offer.meta.originalURL.flatMap(URL.init(string:)),
            isDirty: true,
            keepLastSaved: true,
            regenerateID: false
        )
        resetSessionState(selecting: doc.root.id)
    }

    /// 「忽略（丢弃草稿）」：清空副本，载入最近正式保存版本（无 → 保持当前 clean）。
    func discardDraft() throws {
        try persistence.discardDraft()
        isDirty = persistence.isDirty
        documentID = persistence.documentID
        recovery = persistence.recovery
        commandBus.clearHistory()
        undoRevision += 1
    }

    func load(from url: URL) throws {
        commitEditingIfNeeded()
        let doc = try persistence.load(from: url)
        model.document = doc
        persistence.adopt(document: doc, fileURL: url, isDirty: false,
                          keepLastSaved: false, regenerateID: true)
        resetSessionState(selecting: doc.root.id)
    }

    func save() throws {
        commitEditingIfNeeded()
        try persistence.save(document: model.document)
        isDirty = persistence.isDirty
    }

    func saveAs(to url: URL) throws {
        commitEditingIfNeeded()
        try persistence.saveAs(document: model.document, to: url)
        fileURL = persistence.fileURL
        isDirty = persistence.isDirty
    }

    func markDirtyAndRelayout() {
        isDirty = persistence.noteChange(current: model.document)
        relayout()
        // D1：布局变化（工具栏切换或 ⌘Z/⌘⇧Z 往返）统一触发再适配。
        if model.document.layout != appliedLayoutForFit {
            appliedLayoutForFit = model.document.layout
            fitVersion += 1
        }
    }

    func relayout() {
        snapshot = layoutPipeline.relayout(document: model.document)
    }

    func clearError() {
        errorMessage = nil
    }

    func syncSelectionFromModel() {
        selectedIds = model.selectedIds
        selectionAnchorId = model.selectionAnchorId
        // 换选中集即退出图片级选中（spec §5.2：点空白 / 换选节点均清）。所有换选入口
        // （selectOnly / toggle / 范围选 / replaceSelection / ⌘A / 框选 / undo-redo）都经此收敛点；
        // selectImageBlock 不经此路直接赋值，图片块选中不受影响。
        selectedImageBlock = nil
    }

    func selectOnly(_ id: UUID?) {
        model.selectOnly(id)
        syncSelectionFromModel()
    }

    func toggleInSelection(_ id: UUID) {
        model.toggleInSelection(id)
        syncSelectionFromModel()
    }

    func selectSiblingRange(to id: UUID) {
        model.selectSiblingRange(to: id)
        syncSelectionFromModel()
    }

    func replaceSelection(_ ids: Set<UUID>, anchorId: UUID?) {
        model.replaceSelection(ids, anchorId: anchorId)
        syncSelectionFromModel()
    }

    func clearSelection() {
        model.clearSelection()
        syncSelectionFromModel()
    }

    func copySelection() {
        let tops = model.movableTopLevel(ids: model.selectedIds)
        guard !tops.isEmpty else { return }
        clipboard = ClipboardPayload(
            mode: .copy,
            nodes: tops.compactMap { model.node(id: $0) },
            sourceIds: []
        )
    }

    func cutSelection() {
        let tops = model.movableTopLevel(ids: model.selectedIds)
        guard !tops.isEmpty else { return }
        clipboard = ClipboardPayload(
            mode: .cut,
            nodes: tops.compactMap { model.node(id: $0) },
            sourceIds: tops
        )
        cutSourceIds = Set(tops)
    }

    func cancelCut() {
        clipboard = nil
        cutSourceIds = []
    }

    // MARK: - 搜索

    struct SearchState: Equatable {
        var isOpen = false
        var query = ""
        var matches: [UUID] = []
        var index: Int = -1
        var currentMatchId: UUID? {
            index >= 0 && index < matches.count ? matches[index] : nil
        }
    }

    @Published private(set) var search = SearchState()

    func openSearch() {
        commitEditingIfNeeded()
        search.isOpen = true
        // 已打开：壳层负责聚焦并全选；此处仅保证态
    }

    func closeSearch() {
        search.isOpen = false
    }

    func runSearch(query: String, preferId: UUID? = nil) {
        search.query = query
        search.matches = model.searchMatches(query: query)
        guard !search.matches.isEmpty else {
            search.index = -1
            return
        }
        var idx = 0
        if let preferId, let at = search.matches.firstIndex(of: preferId) {
            idx = at
        }
        revealSearchMatch(idx)
    }

    func revealSearchMatch(_ index: Int) {
        guard !search.matches.isEmpty else { return }
        let n = search.matches.count
        search.index = ((index % n) + n) % n
        let id = search.matches[search.index]

        // 展开通往该节点的全部祖先（复用 setCollapsed：一步 Undo，全已展开 no-op）
        var ancestors: [UUID] = []
        var cur = model.parentId(of: id)
        while let p = cur {
            ancestors.append(p)
            cur = model.parentId(of: p)
        }
        if !ancestors.isEmpty {
            commandBus.execute(.setCollapsed(ids: ancestors, collapsed: false))
        }
        model.selectOnly(id)
        syncSelectionFromModel()
    }

    /// 保持缩放，把命中节点世界矩形中心移到视口中心。
    func centerCamera(on id: UUID, viewport: CGSize) {
        guard let frame = snapshot.frames[id] else { return }
        var cam = camera
        cam.center(on: frame.rect, viewport: viewport)
        commitCamera(cam)
    }

    /// 把当前相机缩放写入 zoomPercent 镜像（工具栏显示）。只在"提交"边界调用，
    /// 不随每帧平移/缩放事件发布（性能 R5）。
    func syncZoomPercent() {
        let p = Int((camera.scale * 100).rounded())
        if p != zoomPercent {
            zoomPercent = p
        }
    }

    /// 非手势相机写入入口（工具栏缩放/适应/加载/居中/重置）：一次赋值 + 一次低频发布
    /// （cameraCommittedRevision 供画布重绘；zoomPercent 供工具栏显示），不随每帧事件发布。
    func commitCamera(_ newValue: Camera) {
        camera = newValue
        cameraCommittedRevision += 1
        syncZoomPercent()
    }

    /// 逻辑图无左右语义：⌘←/⌘→ 与侧向拖放置灰（FR-L4）；切回辐射恢复。
    var canSetSide: Bool {
        model.document.layout != .logic
            && model.selectedIds.contains { model.parentId(of: $0) == model.document.root.id }
    }

    func pasteToPrimary() {
        guard let clipboard, let target = primarySelectedId else { return }
        switch clipboard.mode {
        case .copy:
            guard model.node(id: target) != nil else { return }
            commandBus.execute(.pasteAsChild(payload: clipboard.nodes, parentId: target))
        case .cut:
            let alive = clipboard.sourceIds.filter { model.node(id: $0) != nil }
            guard !alive.isEmpty,
                  model.isValidDropTarget(target, movingIds: Set(alive)) else { return }
            commandBus.execute(.moveToParent(ids: alive, parentId: target))
            cancelCut()
        }
    }

    /// 当前布局（文档属性，随 .ymind 持久化）。改走 setLayout 命令入栈。
    var layout: LayoutKind { model.document.layout }

    func setLayout(_ kind: LayoutKind) {
        commitEditingIfNeeded()
        commandBus.execute(.setLayout(kind: kind))
    }

    func setFill(_ fill: NodeFill?) {
        commitEditingIfNeeded()
        commandBus.execute(.setFill(ids: Array(model.selectedIds), fill: fill))
    }

    // MARK: - 节点图片（FR-G2）

    /// 删除选中的图片块（⌫ 分派）。无图片选中则 no-op。
    func removeSelectedImageBlock() {
        commitEditingIfNeeded()
        guard let selected = selectedImageBlock else { return }
        self.selectedImageBlock = nil   // 删块后回落：选中回节点
        commandBus.execute(.removeImageBlock(id: selected.nodeId, blockId: selected.blockId))
    }

    /// 粘贴/拖入入口：归一 + 追加图片块到节点末尾。要求有选中节点。
    /// 选中图片块时（spec §0-5 最小集：替换 + 删除）→ 替换该块（块 id 不变），
    /// 否则追加到各选中节点末尾（spec §0-4）。
    @discardableResult
    func appendPastedImage(from data: Data) -> Bool {
        commitEditingIfNeeded()
        guard let normalizer = imageNormalizer,
              !model.selectedIds.isEmpty,
              let normalized = normalizer(data) else {
            return false
        }
        // 选中图片块 → 替换（沿 v3「选中图时粘贴覆盖该图」先例；块 id 不变，纹理/导出不碰撞）。
        // 替换后回落图片选中（与删块一致）；nodeId/blockId 失效则回落走追加分支。
        if let selected = selectedImageBlock,
           model.node(id: selected.nodeId)?.blocks.contains(where: { $0.id == selected.blockId }) == true {
            self.selectedImageBlock = nil
            commandBus.execute(
                .replaceImageBlock(id: selected.nodeId, blockId: selected.blockId, image: normalized.data, pixelSize: normalized.pixelSize)
            )
            return true
        }
        self.selectedImageBlock = nil
        for id in Array(model.selectedIds) {
            commandBus.execute(
                .appendImageBlock(id: id, image: normalized.data, pixelSize: normalized.pixelSize)
            )
        }
        return true
    }

    /// 双击图片块：进入图片级选中（节点选中态不变）。
    func selectImageBlock(nodeId: UUID, blockId: UUID) {
        guard model.node(id: nodeId) != nil else { return }
        selectedImageBlock = (nodeId, blockId)
    }

    func clearImageSelection() {
        selectedImageBlock = nil
    }

    func move(_ ids: [UUID], to targetId: UUID) {
        guard model.isValidDropTarget(targetId, movingIds: Set(ids)) else { return }
        commandBus.execute(.moveToParent(ids: ids, parentId: targetId))
    }

    var canCopy: Bool { !model.movableTopLevel(ids: model.selectedIds).isEmpty }
    var canCut: Bool { canCopy }

    var canPaste: Bool {
        guard let clipboard, let target = primarySelectedId else { return false }
        switch clipboard.mode {
        case .copy:
            return model.node(id: target) != nil
        case .cut:
            let alive = clipboard.sourceIds.filter { model.node(id: $0) != nil }
            return !alive.isEmpty && model.isValidDropTarget(target, movingIds: Set(alive))
        }
    }

    func startEditing(_ id: UUID) {
        guard editingController.begin(id: id, currentDraft: draftText, snapshotFrames: snapshot.frames) else { return }
        selectOnly(id)
        draftText = editingController.originalEditingText
        editingId = id
    }

    @discardableResult
    func commitEditingIfNeeded() -> Bool {
        guard editingId != nil else { return false }
        editingController.commit(draftText: draftText)
        editingId = nil
        draftText = ""
        return true
    }

    func cancelEditing() {
        draftText = editingController.originalEditingText
        editingController.cancel()
        editingId = nil
    }

    /// Returns whether the document can be replaced without prompting to discard unsaved changes.
    func prepareReplace() -> Bool {
        commitEditingIfNeeded()
        return !isDirty
    }

    private func wireCommandBus() {
        commandBus.onChange = { [weak self] in
            guard let self else { return }
            syncSelectionFromModel()
            undoRevision += 1
            markDirtyAndRelayout()
            persistence.scheduleAutoSave(document: { self.model.document },
                                         changeCount: { self.undoRevision })
        }
    }

    /// 立即把当前文档写临时副本；失败静默（FR-S1）。internal 供单测直接调用。
    func flushAutoSave() {
        persistence.flushAutoSave(document: model.document, changeCount: undoRevision)
    }

    /// 会话侧状态重置（adopt 已处理持久化态）：选中根、清命令栈、编辑/相机/导入预览/错误清空、
    /// 镜像 persistence 的 fileURL/isDirty/documentID/recovery，末尾统一重布局。
    /// 消除 newDocument/load/loadImported/restore 5 处重复的会话侧重置。
    private func resetSessionState(selecting rootId: UUID) {
        model.selectOnly(rootId)
        syncSelectionFromModel()
        commandBus.clearHistory()
        undoRevision += 1
        // 镜像持久化态（adopt 已重置）：Session 的 @Published 镜像必须同步，壳层直接读这些属性。
        fileURL = persistence.fileURL
        isDirty = persistence.isDirty
        documentID = persistence.documentID
        recovery = persistence.recovery
        selectedImageBlock = nil
        editingId = nil
        draftText = ""
        editingController.cancel()
        commitCamera(Camera())
        importPreview = nil
        errorMessage = nil
        relayout()
        appliedLayoutForFit = model.document.layout
    }
}

struct ImportPreviewState: Equatable {
    let sourceName: String
    let document: MindMapDocument
    var nodeCount: Int
    var depth: Int
}
