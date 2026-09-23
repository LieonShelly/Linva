import Combine
import CoreGraphics
import Foundation

enum DocumentSessionError: Error, Equatable {
    case noFileURL
}

final class DocumentSession: ObservableObject {
    let model: MindMapModel
    let commandBus: CommandBus

    @Published var fileURL: URL?
    @Published var isDirty = false
    @Published var camera = Camera()
    @Published var snapshot: LayoutSnapshot
    @Published private(set) var selectedId: UUID?
    @Published var errorMessage: String?

    private let measure: TextMeasure

    var windowTitle: String {
        let name = fileURL?.lastPathComponent ?? "未命名"
        return isDirty ? "\(name) •" : name
    }

    init(model: MindMapModel? = nil, measure: TextMeasure = TextMeasure()) {
        let model = model ?? MindMapModel.makeNew()
        self.model = model
        self.commandBus = CommandBus(model: model)
        self.measure = measure
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
        fileURL = nil
        isDirty = false
        camera = Camera()
        relayout()
        errorMessage = nil
    }

    func load(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let doc = try YMindCodec.decode(data)
        model.document = doc
        model.selectedId = doc.root.id
        selectedId = doc.root.id
        commandBus.clearHistory()
        fileURL = url
        isDirty = false
        camera = Camera()
        relayout()
        errorMessage = nil
    }

    func save() throws {
        guard let fileURL else {
            throw DocumentSessionError.noFileURL
        }
        try saveAs(to: fileURL)
    }

    func saveAs(to url: URL) throws {
        let data = try YMindCodec.encode(model.document)
        try data.write(to: url, options: .atomic)
        fileURL = url
        isDirty = false
    }

    func markDirtyAndRelayout() {
        isDirty = true
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
            markDirtyAndRelayout()
        }
    }
}
