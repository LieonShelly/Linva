import Combine
import CoreGraphics
import Foundation

enum DocumentSessionError: Error, Equatable {
    case noFileURL
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
    @Published var snapshot: LayoutSnapshot
    @Published private(set) var selectedId: UUID?
    @Published private(set) var editingId: UUID?
    @Published var draftText = ""
    @Published var errorMessage: String?

    private let measure: TextMeasure
    private let securityScopedAccess: SecurityScopedAccess
    private var lastSavedDocument: MindMapDocument
    private var originalEditingText = ""

    var windowTitle: String {
        fileURL?.lastPathComponent ?? "未命名"
    }

    init(
        model: MindMapModel? = nil,
        measure: TextMeasure = TextMeasure(),
        securityScopedAccess: SecurityScopedAccess = SecurityScopedAccess()
    ) {
        let model = model ?? MindMapModel.makeNew()
        self.model = model
        self.commandBus = CommandBus(model: model)
        self.measure = measure
        self.securityScopedAccess = securityScopedAccess
        self.lastSavedDocument = model.document
        self.snapshot = LayoutSnapshot(frames: [:], edges: [])
        self.selectedId = model.selectedId
        wireCommandBus()
        relayout()
    }

    func newDocument() {
        commitEditingIfNeeded()
        let doc = MindMapDocument.blank()
        model.document = doc
        model.selectedId = doc.root.id
        selectedId = doc.root.id
        commandBus.clearHistory()
        undoRevision += 1
        securityScopedAccess.release()
        fileURL = nil
        lastSavedDocument = doc
        isDirty = false
        editingId = nil
        draftText = ""
        originalEditingText = ""
        camera = Camera()
        relayout()
        errorMessage = nil
    }

    func load(from url: URL) throws {
        commitEditingIfNeeded()
        let doc = try securityScopedAccess.replace(with: url) {
            let data = try Data(contentsOf: url)
            return try YMindCodec.decode(data)
        }
        model.document = doc
        model.selectedId = doc.root.id
        selectedId = doc.root.id
        commandBus.clearHistory()
        undoRevision += 1
        fileURL = url
        lastSavedDocument = doc
        isDirty = false
        editingId = nil
        draftText = ""
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

    func select(_ id: UUID?) {
        model.select(id)
        selectedId = model.selectedId
    }

    func startEditing(_ id: UUID) {
        guard let node = model.node(id: id),
              snapshot.frames[id] != nil else {
            return
        }
        if editingId != nil, editingId != id {
            commitEditingIfNeeded()
        }
        select(id)
        originalEditingText = node.text
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
        if committedText != originalEditingText {
            commandBus.execute(
                .setText(id: editingId, old: originalEditingText, new: committedText)
            )
        }
        originalEditingText = ""
        return true
    }

    func cancelEditing() {
        draftText = originalEditingText
        originalEditingText = ""
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
            selectedId = model.selectedId
            undoRevision += 1
            markDirtyAndRelayout()
        }
    }
}
