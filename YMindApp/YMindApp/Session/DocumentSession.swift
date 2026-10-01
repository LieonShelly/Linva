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

final class SecurityScopedAccess {
    typealias StartAccess = (URL) -> Bool
    typealias StopAccess = (URL) -> Void

    private let startAccess: StartAccess
    private let stopAccess: StopAccess
    private var activeURL: URL?

    init(
        startAccess: @escaping StartAccess = { $0.startAccessingSecurityScopedResource() },
        stopAccess: @escaping StopAccess = { $0.stopAccessingSecurityScopedResource() }
    ) {
        self.startAccess = startAccess
        self.stopAccess = stopAccess
    }

    deinit {
        release()
    }

    /// Performs I/O while access is active, then adopts a successfully-started scope.
    func replace<T>(with url: URL, operation: () throws -> T) rethrows -> T {
        if activeURL == url {
            return try operation()
        }

        let didStart = startAccess(url)
        do {
            let result = try operation()
            release()
            if didStart {
                activeURL = url
            }
            return result
        } catch {
            if didStart {
                stopAccess(url)
            }
            throw error
        }
    }

    /// Performs I/O using the held scope, or a balanced temporary scope.
    func withAccess<T>(to url: URL, operation: () throws -> T) rethrows -> T {
        if activeURL == url {
            return try operation()
        }

        let didStart = startAccess(url)
        defer {
            if didStart {
                stopAccess(url)
            }
        }
        return try operation()
    }

    func release() {
        guard let activeURL else { return }
        stopAccess(activeURL)
        self.activeURL = nil
    }
}

final class DocumentSession: ObservableObject {
    let model: MindMapModel
    let commandBus: CommandBus

    @Published var fileURL: URL?
    @Published var isDirty = false
    @Published private(set) var undoRevision = 0
    @Published var camera = Camera()
    @Published var canvasTool: CanvasTool = .select
    @Published var snapshot: LayoutSnapshot
    @Published private(set) var selectedIds: Set<UUID> = []
    @Published private(set) var selectionAnchorId: UUID?
    @Published private(set) var editingId: UUID?
    @Published var draftText = ""
    @Published var errorMessage: String?
    @Published private(set) var clipboard: ClipboardPayload?
    @Published private(set) var cutSourceIds: Set<UUID> = []
    /// 图片级选中（节点内子元素）；不入命令栈，同时最多一个。
    @Published private(set) var selectedImageId: UUID?
    /// 图片归一注入点（App 组合根赋 ImageNormalizer.normalize；测试注入 stub）。Session 白名单无 ImageIO。
    var imageNormalizer: ((Data) -> (data: Data, pixelSize: ImagePixelSize)?)?
    @Published var importPreview: ImportPreviewState?
    /// 自动保存/恢复配对用（未命名文档亦然）。导入 plan 已引入，勿重复声明。
    var documentID = UUID()
    /// 启动扫描待恢复会话提示（Task 3 填充；newDocument/load 时清空）。
    @Published var recovery: RecoveryOffer?

    private let measure: TextMeasure
    private let securityScopedAccess: SecurityScopedAccess
    private let autosaveStore: AutosaveStore
    private var autoSaveDebounce: AnyCancellable?
    private var lastSavedDocument: MindMapDocument
    private var originalEditingText = ""
    /// 编辑提交的 Undo 基线（内容流聚拢前的块序列）。
    private var originalBlocks: [ContentBlock] = []

    var primarySelectedId: UUID? { model.primarySelectedId }

    var windowTitle: String {
        fileURL?.lastPathComponent ?? "未命名"
    }

    init(
        model: MindMapModel? = nil,
        measure: TextMeasure = TextMeasure(),
        securityScopedAccess: SecurityScopedAccess = SecurityScopedAccess(),
        autosaveStore: AutosaveStore = AutosaveStore()
    ) {
        let model = model ?? MindMapModel.makeNew()
        self.model = model
        self.commandBus = CommandBus(model: model)
        self.measure = measure
        self.securityScopedAccess = securityScopedAccess
        self.autosaveStore = autosaveStore
        self.lastSavedDocument = model.document
        self.snapshot = LayoutSnapshot(frames: [:], edges: [])
        self.selectedIds = model.selectedIds
        self.selectionAnchorId = model.selectionAnchorId
        wireCommandBus()
        relayout()
    }

    func newDocument() {
        commitEditingIfNeeded()
        let doc = MindMapDocument.blank()
        model.document = doc
        model.selectOnly(doc.root.id)
        syncSelectionFromModel()
        commandBus.clearHistory()
        undoRevision += 1
        securityScopedAccess.release()
        fileURL = nil
        lastSavedDocument = doc
        isDirty = false
        documentID = UUID()
        recovery = nil
        selectedImageId = nil
        editingId = nil
        draftText = ""
        originalBlocks = []
        originalEditingText = ""
        camera = Camera()
        relayout()
        errorMessage = nil
    }

    /// 载入一次导入解析出的新树为当前文档：等同「打开」语义但 fileURL=nil、isDirty=true。
    func loadImported(_ document: MindMapDocument) {
        commitEditingIfNeeded()
        model.document = document
        model.selectOnly(document.root.id)
        syncSelectionFromModel()
        commandBus.clearHistory()
        undoRevision += 1
        fileURL = nil
        // 注意：不要在此把 lastSavedDocument 设为新文档 —— 导入文档没有磁盘文件，
        // lastSavedDocument 保持导入前的旧值，撤销回载入态时 isDirty 仍需保持 true。
        isDirty = true
        documentID = UUID()
        recovery = nil
        selectedImageId = nil
        editingId = nil
        draftText = ""
        originalBlocks = []
        originalEditingText = ""
        camera = Camera()
        importPreview = nil
        relayout()
        errorMessage = nil
    }

    func cancelImport() {
        importPreview = nil
        errorMessage = nil
    }

    // MARK: - 自动保存恢复（Task 3）

    /// 启动扫描：若存在未保存副本，返回「最新一份」的 offer；否则 nil。
    @discardableResult
    func scanForRecovery() -> RecoveryOffer? {
        guard let meta = autosaveStore.latestPending() else { return nil }
        let offer = RecoveryOffer(meta: meta)
        recovery = offer
        return offer
    }

    /// 「恢复更改」：载入副本为当前文档，标记未保存，删除该副本。
    func restore(draftFrom offer: RecoveryOffer) throws {
        let doc = try autosaveStore.load(documentID: offer.meta.documentID)
        commitEditingIfNeeded()
        model.document = doc
        model.selectOnly(doc.root.id)
        syncSelectionFromModel()
        commandBus.clearHistory()
        undoRevision += 1
        // 有原文件则恢复其 URL；未命名则保持 nil
        fileURL = offer.meta.originalURL.flatMap(URL.init(string:))
        // 注意：不要在此把 lastSavedDocument 设为恢复的草稿 —— 草稿没有磁盘文件，
        // lastSavedDocument 保持原值，撤销回载入态时 isDirty 仍需保持 true（同 loadImported）。
        isDirty = true
        documentID = offer.meta.documentID
        editingId = nil
        draftText = ""
        originalBlocks = []
        originalEditingText = ""
        selectedImageId = nil
        camera = Camera()
        recovery = nil
        relayout()
        errorMessage = nil
        try? autosaveStore.delete(documentID: offer.meta.documentID)
        try? autosaveStore.clearAll()   // 恢复后清其余残留（忽略清全部；恢复也顺手清，避免再提示）
    }

    /// 「忽略（丢弃草稿）」：清空副本，载入最近正式保存版本（无 → 保持当前 clean）。
    func discardDraft() throws {
        commandBus.clearHistory()
        undoRevision += 1
        isDirty = false
        recovery = nil
        try autosaveStore.clearAll()
        documentID = UUID()
    }

    func load(from url: URL) throws {
        commitEditingIfNeeded()
        let doc = try securityScopedAccess.replace(with: url) {
            let data = try Data(contentsOf: url)
            return try YMindCodec.decode(data)
        }
        model.document = doc
        model.selectOnly(doc.root.id)
        syncSelectionFromModel()
        commandBus.clearHistory()
        undoRevision += 1
        fileURL = url
        lastSavedDocument = doc
        isDirty = false
        documentID = UUID()
        recovery = nil
        selectedImageId = nil
        editingId = nil
        draftText = ""
        originalBlocks = []
        originalEditingText = ""
        camera = Camera()
        relayout()
        errorMessage = nil
    }

    func save() throws {
        commitEditingIfNeeded()
        guard let fileURL else {
            throw DocumentSessionError.noFileURL
        }
        let data = try YMindCodec.encode(model.document)
        try securityScopedAccess.withAccess(to: fileURL) {
            try data.write(to: fileURL, options: .atomic)
        }
        lastSavedDocument = model.document
        isDirty = false
        try? autosaveStore.delete(documentID: documentID)
    }

    func saveAs(to url: URL) throws {
        commitEditingIfNeeded()
        let data = try YMindCodec.encode(model.document)
        try securityScopedAccess.replace(with: url) {
            try data.write(to: url, options: .atomic)
        }
        fileURL = url
        lastSavedDocument = model.document
        isDirty = false
        try? autosaveStore.delete(documentID: documentID)
    }

    func markDirtyAndRelayout() {
        isDirty = model.document != lastSavedDocument
        relayout()
    }

    func relayout() {
        snapshot = RadialLayout.layout(document: model.document, measure: measure)
    }

    func clearError() {
        errorMessage = nil
    }

    func syncSelectionFromModel() {
        selectedIds = model.selectedIds
        selectionAnchorId = model.selectionAnchorId
    }

    func selectOnly(_ id: UUID?) {
        model.selectOnly(id)
        syncSelectionFromModel()
        // 换选中集即退出图片级选中（spec §5.2：点空白 / 换选节点均清；selectImage 不经此路，安全）。
        selectedImageId = nil
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
        selectedImageId = nil   // 点空白清图片选中（spec §5.2）
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
        camera = cam
    }

    var canSetSide: Bool {
        model.selectedIds.contains { model.parentId(of: $0) == model.document.root.id }
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

    func setFill(_ fill: NodeFill?) {
        commitEditingIfNeeded()
        commandBus.execute(.setFill(ids: Array(model.selectedIds), fill: fill))
    }

    // MARK: - 节点图片（FR-G2）

    /// 过渡壳：⌫ 清图 → 删除选中节点首个图片块；非清除 → 追加。Task 3 由 removeSelectedImageBlock 取代。
    func setImage(_ image: Data?, pixelSize: ImagePixelSize?) {
        commitEditingIfNeeded()
        if let image, let pixelSize {
            self.selectedImageId = nil
            for id in Array(model.selectedIds) {
                commandBus.execute(.appendImageBlock(id: id, image: image, pixelSize: pixelSize))
            }
            return
        }
        // 清除：删除选中节点（或 ⌫ 分派目标）的首个图片块。
        let targetIds = selectedImageId.map { [$0] } ?? Array(model.selectedIds)
        self.selectedImageId = nil
        for id in targetIds {
            guard let node = model.node(id: id),
                  let first = node.blocks.first(where: {
                      if case .image = $0.kind { return true } else { return false }
                  }) else { continue }
            commandBus.execute(.removeImageBlock(id: id, blockId: first.id))
        }
    }

    /// 粘贴/拖入入口：归一 + 追加图片块到节点末尾。要求有选中节点。
    @discardableResult
    func appendPastedImage(from data: Data) -> Bool {
        commitEditingIfNeeded()
        guard let normalizer = imageNormalizer,
              !model.selectedIds.isEmpty,
              let normalized = normalizer(data) else {
            return false
        }
        self.selectedImageId = nil
        for id in Array(model.selectedIds) {
            commandBus.execute(
                .appendImageBlock(id: id, image: normalized.data, pixelSize: normalized.pixelSize)
            )
        }
        return true
    }

    /// 过渡壳：Task 3 前 ContentView/CanvasMetalView 仍调用旧名；Task 3 切到 appendPastedImage 后删除。
    @discardableResult
    func setPastedImage(from data: Data) -> Bool {
        appendPastedImage(from: data)
    }

    /// 双击图片区域：进入图片级选中（节点选中态不变）。
    func selectImage(_ id: UUID) {
        guard model.node(id: id) != nil else { return }
        selectedImageId = id
    }

    func clearImageSelection() {
        selectedImageId = nil
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
        guard let node = model.node(id: id),
              snapshot.frames[id] != nil else {
            return
        }
        if editingId != nil, editingId != id {
            commitEditingIfNeeded()
        }
        selectOnly(id)
        originalEditingText = node.text
        originalBlocks = node.blocks      // 新增：Undo 基线
        draftText = node.text
        editingId = id
    }

    @discardableResult
    func commitEditingIfNeeded() -> Bool {
        guard let editingId else { return false }
        let committedText = draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "未命名"
            : draftText
        self.editingId = nil
        // 聚拢规则：文本合并单块；图片按原相对顺序聚拢单侧——
        // 原序列首个非空块是图片 → [images] + [text]（图上文下）；否则 [text] + [images]（文上图下）。
        let images = originalBlocks.filter { block in
            if case .image = block.kind { return true } else { return false }
        }
        let firstBlockIsImage: Bool = {
            guard let first = originalBlocks.first else { return false }
            if case .image = first.kind { return true } else { return false }
        }()
        var newBlocks: [ContentBlock]
        if firstBlockIsImage {
            newBlocks = images + [ContentBlock(id: UUID(), kind: .text(committedText))]
        } else {
            newBlocks = [ContentBlock(id: UUID(), kind: .text(committedText))] + images
        }
        if newBlocks != originalBlocks {
            commandBus.execute(
                .setBlocks(id: editingId, old: originalBlocks, new: newBlocks)
            )
        }
        originalBlocks = []
        originalEditingText = ""
        return true
    }

    func cancelEditing() {
        draftText = originalEditingText
        originalEditingText = ""
        originalBlocks = []
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
            scheduleAutoSave()
        }
    }

    /// 脏后 2s 防抖写副本（FR-S1）。重订阅每次 cancel 旧的延时。
    private func scheduleAutoSave() {
        autoSaveDebounce = Just(())
            .delay(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.flushAutoSave() }
    }

    /// 立即把当前文档写临时副本；失败静默（FR-S1）。internal 供单测直接调用。
    func flushAutoSave() {
        guard hasLoadedEditableContent else { return }
        let meta = AutosaveMeta(
            documentID: documentID,
            originalURL: fileURL?.absoluteString,
            savedAt: Date(),
            changeCount: pendingChangeCount(),
            rootText: model.document.root.text
        )
        try? autosaveStore.write(document: model.document, meta: meta)
    }

    /// 只对已加载且有内容的文档写副本（不建空树副本）。
    private var hasLoadedEditableContent: Bool {
        // fileURL != nil（已保存）或 isDirty（有改动）
        fileURL != nil || isDirty
    }

    /// 距上次保存的变化计数：复用 undoRevision（每次命令/撤销/重做 +1）。
    private func pendingChangeCount() -> Int {
        undoRevision
    }
}

struct ImportPreviewState: Equatable {
    let sourceName: String
    let document: MindMapDocument
    var nodeCount: Int
    var depth: Int
}
