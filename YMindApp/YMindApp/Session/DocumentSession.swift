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

    /// Takes ownership of an already-active panel scope, or starts a new scope when possible.
    func replace(with url: URL, accessAlreadyStarted: Bool) {
        release()
        if accessAlreadyStarted || startAccess(url) {
            activeURL = url
        }
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
    @Published var editingId: UUID?
    @Published var errorMessage: String?

    private let measure: TextMeasure
    private let securityScopedAccess: SecurityScopedAccess
    private var lastSavedDocument: MindMapDocument

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
        camera = Camera()
        relayout()
        errorMessage = nil
    }

    func load(from url: URL, securityScopeAlreadyActive: Bool = false) throws {
        var adoptedScope = false
        defer {
            if securityScopeAlreadyActive && !adoptedScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        let doc = try YMindCodec.decode(data)
        securityScopedAccess.replace(
            with: url,
            accessAlreadyStarted: securityScopeAlreadyActive
        )
        adoptedScope = true
        model.document = doc
        model.selectedId = doc.root.id
        selectedId = doc.root.id
        commandBus.clearHistory()
        undoRevision += 1
        fileURL = url
        lastSavedDocument = doc
        isDirty = false
        editingId = nil
        camera = Camera()
        relayout()
        errorMessage = nil
    }

    func save() throws {
        guard let fileURL else {
            throw DocumentSessionError.noFileURL
        }
        let data = try YMindCodec.encode(model.document)
        try data.write(to: fileURL, options: .atomic)
        lastSavedDocument = model.document
        isDirty = false
    }

    func saveAs(to url: URL, securityScopeAlreadyActive: Bool = false) throws {
        var adoptedScope = false
        defer {
            if securityScopeAlreadyActive && !adoptedScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try YMindCodec.encode(model.document)
        try data.write(to: url, options: .atomic)
        securityScopedAccess.replace(
            with: url,
            accessAlreadyStarted: securityScopeAlreadyActive
        )
        adoptedScope = true
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

    /// Returns whether the document can be replaced without prompting to discard unsaved changes.
    func prepareReplace() -> Bool {
        !isDirty
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
