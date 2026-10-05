// LinvaApp/LinvaApp/Session/DocumentPersistence.swift
import Combine
import Foundation

/// 持久化子域（SRP）：文件 I/O、脏判定、自动保存防抖、崩溃恢复、生命周期 adopt 模板。
/// DocumentSession 镜像其 fileURL/isDirty/documentID/recovery 到 @Published。
final class DocumentPersistence {
    private let backend: PersistenceBackend
    private let securityScopedAccess: SecurityScopedAccess
    private let autosaveStore: AutosaveStore
    private var autoSaveDebounce: AnyCancellable?

    private(set) var fileURL: URL?
    private(set) var lastSavedDocument: MindMapDocument
    private(set) var documentID: UUID
    private(set) var isDirty = false
    private(set) var recovery: RecoveryOffer?

    init(
        backend: PersistenceBackend = LinvaFilePersistence(),
        securityScopedAccess: SecurityScopedAccess = SecurityScopedAccess(),
        autosaveStore: AutosaveStore = AutosaveStore()
    ) {
        self.backend = backend
        self.securityScopedAccess = securityScopedAccess
        self.autosaveStore = autosaveStore
        self.lastSavedDocument = MindMapDocument.blank()
        self.documentID = UUID()
    }

    // MARK: - adopt 模板（生命周期状态重置）

    /// 采纳一份文档为当前文档，统一重置持久化态（消除 newDocument/load/loadImported/restore 的重复重置）。
    /// - Parameters:
    ///   - keepLastSaved: true 保留 lastSavedDocument（导入/恢复：撤销回载入态时 isDirty 仍 true）
    ///   - regenerateID: true 生成新 documentID
    ///   - clearRecovery: true 清 recovery（默认）
    func adopt(
        document: MindMapDocument,
        fileURL: URL?,
        isDirty: Bool,
        keepLastSaved: Bool,
        regenerateID: Bool,
        clearRecovery: Bool = true
    ) {
        self.fileURL = fileURL
        self.isDirty = isDirty
        if !keepLastSaved { self.lastSavedDocument = document }
        if regenerateID { self.documentID = UUID() }
        if clearRecovery { self.recovery = nil }
    }

    /// 改树后的脏判定：当前文档 ≠ lastSaved → 脏。
    func noteChange(current: MindMapDocument) -> Bool {
        isDirty = current != lastSavedDocument
        return isDirty
    }

    // MARK: - 文件 I/O

    func load(from url: URL) throws -> MindMapDocument {
        let doc = try securityScopedAccess.replace(with: url) {
            let data = try backend.readData(from: url)
            return try LinvaCodec.decode(data)
        }
        // 记录源 URL（Session.load 再 adopt 以完成 lastSaved/documentID/recovery 重置）。
        fileURL = url
        return doc
    }

    func save(document: MindMapDocument) throws {
        guard let fileURL else {
            throw DocumentSessionError.noFileURL
        }
        let data = try LinvaCodec.encode(document)
        try securityScopedAccess.withAccess(to: fileURL) {
            try backend.writeData(data, to: fileURL)
        }
        lastSavedDocument = document
        isDirty = false
        try? autosaveStore.delete(documentID: documentID)
    }

    func saveAs(document: MindMapDocument, to url: URL) throws {
        let data = try LinvaCodec.encode(document)
        try securityScopedAccess.replace(with: url) {
            try backend.writeData(data, to: url)
        }
        fileURL = url
        lastSavedDocument = document
        isDirty = false
        try? autosaveStore.delete(documentID: documentID)
    }

    // MARK: - 自动保存

    /// 脏后 2s 防抖写副本（FR-S1）。每次调用 cancel 旧的延时。
    func scheduleAutoSave(document: @escaping () -> MindMapDocument, changeCount: @escaping () -> Int) {
        autoSaveDebounce = Just(())
            .delay(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.flushAutoSave(document: document(), changeCount: changeCount())
            }
    }

    /// 立即把当前文档写临时副本；失败静默。internal 供 Session.flushAutoSave 转发。
    func flushAutoSave(document: MindMapDocument, changeCount: Int) {
        guard hasLoadedEditableContent else { return }
        let meta = AutosaveMeta(
            documentID: documentID,
            originalURL: fileURL?.absoluteString,
            savedAt: Date(),
            changeCount: changeCount,
            rootText: document.root.text
        )
        try? autosaveStore.write(document: document, meta: meta)
    }

    private var hasLoadedEditableContent: Bool {
        fileURL != nil || isDirty
    }

    // MARK: - 崩溃恢复

    @discardableResult
    func scanForRecovery() -> RecoveryOffer? {
        guard let meta = autosaveStore.latestPending() else { return nil }
        let offer = RecoveryOffer(meta: meta)
        recovery = offer
        return offer
    }

    /// 载入副本并删副本（含清残留）；不 adopt（由 Session 在 commitEditingIfNeeded 后调 adopt）。
    func restore(draftFrom offer: RecoveryOffer) throws -> MindMapDocument {
        let doc = try autosaveStore.load(documentID: offer.meta.documentID)
        try? autosaveStore.delete(documentID: offer.meta.documentID)
        try? autosaveStore.clearAll()
        // 草稿无磁盘文件：载入态即视为未保存（与 loadImported 同语义）。
        isDirty = true
        return doc
    }

    func discardDraft() throws {
        isDirty = false
        recovery = nil
        try autosaveStore.clearAll()
        documentID = UUID()
    }
}
