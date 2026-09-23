//
//  YMindAppApp.swift
//  YMindApp
//
//  Created by 李仁军 on 2026/9/24.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let yMindDocument = UTType(
        exportedAs: "com.ymind.document",
        conformingTo: .data
    )
}

@main
struct YMindAppApp: App {
    @StateObject private var session = DocumentSession()

    var body: some Scene {
        WindowGroup {
            ContentView(session: session)
                .background(WindowStateBridge(session: session))
        }
        .commands {
            DocumentCommands(session: session)
        }
    }
}

private struct DocumentCommands: Commands {
    @ObservedObject var session: DocumentSession

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建") {
                DocumentWorkflow.newDocument(session)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("打开…") {
                DocumentWorkflow.open(session)
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button("保存") {
                _ = DocumentWorkflow.save(session)
            }
            .keyboardShortcut("s", modifiers: .command)

            Button("另存为…") {
                _ = DocumentWorkflow.saveAs(session)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .undoRedo) {
            Button("撤销") {
                session.commandBus.undo()
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!session.commandBus.canUndo)

            Button("重做") {
                session.commandBus.redo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!session.commandBus.canRedo)
        }
    }
}

@MainActor
private enum DocumentWorkflow {
    static func newDocument(_ session: DocumentSession) {
        guard confirmReplacement(of: session) else { return }
        session.newDocument()
    }

    static func open(_ session: DocumentSession) {
        guard confirmReplacement(of: session) else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.yMindDocument]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            try session.load(from: url)
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    static func save(_ session: DocumentSession) -> Bool {
        guard session.fileURL != nil else {
            return saveAs(session)
        }

        do {
            try session.save()
            return true
        } catch {
            session.errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    static func saveAs(_ session: DocumentSession) -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.yMindDocument]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFilename(for: session)

        guard panel.runModal() == .OK, let url = panel.url else { return false }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            try session.saveAs(to: url)
            return true
        } catch {
            session.errorMessage = error.localizedDescription
            return false
        }
    }

    static func confirmReplacement(of session: DocumentSession) -> Bool {
        guard session.isDirty else { return true }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "要保存对“\(session.windowTitle.replacingOccurrences(of: " •", with: ""))”的更改吗？"
        alert.informativeText = "如果不保存，更改将会丢失。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "不保存")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return save(session)
        case .alertThirdButtonReturn:
            return true
        default:
            return false
        }
    }

    private static func suggestedFilename(for session: DocumentSession) -> String {
        if let fileURL = session.fileURL {
            return fileURL.lastPathComponent
        }
        return "未命名.ymind"
    }
}

private struct WindowStateBridge: NSViewRepresentable {
    @ObservedObject var session: DocumentSession

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeNSView(context: Context) -> WindowReaderView {
        let view = WindowReaderView()
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ view: WindowReaderView, context: Context) {
        context.coordinator.updateWindowState()
    }

    static func dismantleNSView(_ view: WindowReaderView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        private let session: DocumentSession
        private weak var window: NSWindow?
        private weak var previousDelegate: NSWindowDelegate?

        init(session: DocumentSession) {
            self.session = session
        }

        func attach(to window: NSWindow?) {
            guard let window, self.window !== window else {
                updateWindowState()
                return
            }
            detach()
            self.window = window
            previousDelegate = window.delegate
            window.delegate = self
            updateWindowState()
        }

        func detach() {
            guard let window else { return }
            if window.delegate === self {
                window.delegate = previousDelegate
            }
            self.window = nil
            previousDelegate = nil
        }

        func updateWindowState() {
            window?.title = session.windowTitle
            window?.representedURL = session.fileURL
            window?.isDocumentEdited = session.isDirty
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard DocumentWorkflow.confirmReplacement(of: session) else {
                return false
            }
            return previousDelegate?.windowShouldClose?(sender) ?? true
        }
    }
}

private final class WindowReaderView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}
