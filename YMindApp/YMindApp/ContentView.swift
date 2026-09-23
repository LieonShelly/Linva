//
//  ContentView.swift
//  YMindApp
//
//  Created by 李仁军 on 2026/9/24.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var session = DocumentSession()
    @State private var editingId: UUID?
    @State private var draft = ""
    @State private var originalText = ""

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                CanvasMetalView(
                    session: session,
                    onSelect: handleSelection,
                    onEdit: startEditing,
                    onAddChild: addChild,
                    onAddSibling: addSibling,
                    onDelete: deleteSelected
                )

                if let editingId,
                   let frame = session.snapshot.frames[editingId] {
                    NodeEditorOverlay(
                        screenRect: screenRect(for: frame),
                        isRoot: frame.isRoot,
                        text: $draft,
                        onCommit: commitEditing,
                        onCancel: cancelEditing
                    )
                }

                if let errorMessage = session.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding()
                        .accessibilityLabel("画布错误：\(errorMessage)")
                }
            }
            .toolbar {
                MainToolbar(
                    hasSelection: selectedNode != nil,
                    isRootSelected: session.selectedId == session.model.document.root.id,
                    canToggleCollapse: !(selectedNode?.children.isEmpty ?? true),
                    isCollapsed: selectedNode?.collapsed ?? false,
                    zoomPercent: Int((session.camera.scale * 100).rounded()),
                    addChild: addChild,
                    addSibling: addSibling,
                    toggleCollapse: toggleCollapse,
                    delete: deleteSelected,
                    zoomOut: { zoom(by: 1 / 1.12, viewport: geometry.size) },
                    zoomIn: { zoom(by: 1.12, viewport: geometry.size) },
                    fit: { fit(viewport: geometry.size) }
                )
            }
        }
        .frame(minWidth: 640, minHeight: 420)
    }

    private var selectedNode: Node? {
        session.selectedId.flatMap(session.model.node(id:))
    }

    private func handleSelection(_ id: UUID?) {
        if editingId != nil, editingId != id {
            commitEditing()
        }
        session.select(id)
    }

    private func startEditing(_ id: UUID) {
        guard let node = session.model.node(id: id),
              session.snapshot.frames[id] != nil else {
            return
        }
        if editingId != nil, editingId != id {
            commitEditing()
        }
        session.select(id)
        originalText = node.text
        draft = node.text
        editingId = id
    }

    private func commitEditing() {
        guard let editingId else { return }
        let committedText = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "未命名"
            : draft
        self.editingId = nil
        if committedText != originalText {
            session.commandBus.execute(
                .setText(id: editingId, old: originalText, new: committedText)
            )
        }
    }

    private func cancelEditing() {
        editingId = nil
        draft = originalText
    }

    private func addChild() {
        if editingId != nil {
            commitEditing()
        }
        guard let selectedId = session.selectedId else { return }
        if session.model.node(id: selectedId)?.collapsed == true {
            session.commandBus.execute(.toggleCollapse(id: selectedId))
        }
        session.commandBus.execute(.addChild(parentId: selectedId, text: "新主题"))
        if let newId = session.selectedId {
            startEditing(newId)
        }
    }

    private func addSibling() {
        if editingId != nil {
            commitEditing()
        }
        guard let selectedId = session.selectedId,
              selectedId != session.model.document.root.id else {
            return
        }
        session.commandBus.execute(.addSibling(selectedId: selectedId, text: "新主题"))
        if let newId = session.selectedId {
            startEditing(newId)
        }
    }

    private func toggleCollapse() {
        if editingId != nil {
            commitEditing()
        }
        guard let selectedId = session.selectedId,
              session.model.node(id: selectedId)?.children.isEmpty == false else {
            return
        }
        session.commandBus.execute(.toggleCollapse(id: selectedId))
    }

    private func deleteSelected() {
        if editingId != nil {
            commitEditing()
        }
        guard let selectedId = session.selectedId,
              selectedId != session.model.document.root.id else {
            return
        }
        session.commandBus.execute(.delete(id: selectedId))
    }

    private func zoom(by factor: CGFloat, viewport: CGSize) {
        let anchor = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        let worldAnchor = session.camera.screenToWorld(anchor)
        let newScale = min(max(session.camera.scale * factor, 0.2), 4)
        session.camera.scale = newScale
        session.camera.translation = CGPoint(
            x: anchor.x - worldAnchor.x * newScale,
            y: anchor.y - worldAnchor.y * newScale
        )
    }

    private func fit(viewport: CGSize) {
        let contentBounds = session.snapshot.frames.values.reduce(CGRect.null) {
            $0.union($1.rect)
        }
        var camera = session.camera
        camera.fit(contentBounds: contentBounds, viewport: viewport)
        session.camera = camera
    }

    private func screenRect(for frame: NodeFrame) -> CGRect {
        let origin = session.camera.worldToScreen(frame.rect.origin)
        return CGRect(
            origin: origin,
            size: CGSize(
                width: frame.rect.width * session.camera.scale,
                height: frame.rect.height * session.camera.scale
            )
        )
    }
}

#Preview {
    ContentView()
}
