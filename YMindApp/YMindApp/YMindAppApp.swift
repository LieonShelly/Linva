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
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session: DocumentSession

    init() {
        let session = DocumentSession()
        _session = StateObject(wrappedValue: session)
        appDelegate.session = session
    }

    var body: some Scene {
        WindowGroup {
            ContentView(session: session)
                .background(WindowStateBridge(session: session))
                .onOpenURL { url in
                    DocumentWorkflow.open(url, in: session)
                }
        }
        .commands {
            DocumentCommands(session: session)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var session: DocumentSession?
    var confirmationHandler: (DocumentSession) -> Bool = {
        DocumentWorkflow.confirmReplacement(of: $0)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let session else { return .terminateNow }
        return confirmationHandler(session) ? .terminateNow : .terminateCancel
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
                if session.editingId != nil {
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                } else {
                    session.commandBus.undo()
                }
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(session.editingId == nil && !session.commandBus.canUndo)

            Button("重做") {
                if session.editingId != nil {
                    NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                } else {
                    session.commandBus.redo()
                }
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(session.editingId == nil && !session.commandBus.canRedo)
        }

        CommandGroup(after: .undoRedo) {
            Button("搜索…") {
                session.openSearch()
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("查找下一个") {
                session.revealSearchMatch(session.search.index + 1)
            }
            .keyboardShortcut("g", modifiers: .command)

            Button("查找上一个") {
                session.revealSearchMatch(session.search.index - 1)
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])

            Divider()

            Button("移到左侧") {
                _ = setSide(session, .left)
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(!session.canSetSide)

            Button("移到右侧") {
                _ = setSide(session, .right)
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(!session.canSetSide)
        }
    }

    @discardableResult
    private func setSide(_ session: DocumentSession, _ side: Side) -> Bool {
        session.commitEditingIfNeeded()
        let ids = Array(session.selectedIds)
        guard session.canSetSide else { return false }
        session.commandBus.execute(.setSide(ids: ids, side: side))
        return true
    }
}

@MainActor
enum DocumentWorkflow {
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

        do {
            try session.load(from: url)
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }

    static func open(_ url: URL, in session: DocumentSession) {
        guard url.pathExtension.lowercased() == "ymind",
              confirmReplacement(of: session) else {
            return
        }

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
        session.commitEditingIfNeeded()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.yMindDocument]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFilename(for: session)

        guard panel.runModal() == .OK, let url = panel.url else { return false }

        do {
            try session.saveAs(to: url)
            return true
        } catch {
            session.errorMessage = error.localizedDescription
            return false
        }
    }

    static func confirmReplacement(of session: DocumentSession) -> Bool {
        session.commitEditingIfNeeded()
        guard session.isDirty else { return true }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "要保存对“\(session.windowTitle)”的更改吗？"
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

        override func responds(to aSelector: Selector!) -> Bool {
            super.responds(to: aSelector)
                || previousDelegate?.responds(to: aSelector) == true
        }

        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            if previousDelegate?.responds(to: aSelector) == true {
                return previousDelegate
            }
            return super.forwardingTarget(for: aSelector)
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
