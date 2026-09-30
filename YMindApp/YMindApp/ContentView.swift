//
//  ContentView.swift
//  YMindApp
//
//  Created by 李仁军 on 2026/9/24.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var session: DocumentSession
    @State private var canvasFocusRequest = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                CanvasMetalView(
                    session: session,
                    focusRequest: canvasFocusRequest,
                    actions: CanvasActions(
                        select: handleSelection,
                        marqueeSelect: handleMarqueeSelect,
                        edit: startEditing,
                        commitEditing: commitEditing,
                        toggleCollapse: toggleCollapse,
                        toggleCollapseSelection: toggleCollapseSelection,
                        selectAll: selectAll,
                        addChild: addChild,
                        addSibling: addSibling,
                        delete: deleteSelected,
                        move: move,
                        insertSiblings: { ids, anchorId, position in
                            if session.editingId != nil { commitEditing() }
                            session.commandBus.execute(.insertSiblings(ids: ids, anchorId: anchorId, position: position))
                        },
                        setSide: { ids, side in
                            if session.editingId != nil { commitEditing() }
                            session.commandBus.execute(.setSide(ids: ids, side: side))
                        },
                        applyRootSide: { ids, side in
                            if session.editingId != nil { commitEditing() }
                            session.commandBus.execute(.applyRootSide(ids: ids, side: side))
                        },
                        copy: copySelection,
                        cut: cutSelection,
                        paste: paste,
                        cancelCut: cancelCut
                    )
                )

                if let editingId = session.editingId,
                   let frame = session.snapshot.frames[editingId] {
                    NodeEditorOverlay(
                        screenRect: screenRect(for: frame),
                        isRoot: frame.isRoot,
                        text: $session.draftText,
                        onCommit: commitEditing,
                        onCancel: cancelEditing
                    )
                }

                if session.search.isOpen {
                    SearchBar(session: session)
                }

                if let errorMessage = session.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding()
                        .accessibilityLabel("画布错误：\(errorMessage)")
                }

                if let offer = session.recovery {
                    RecoveryBannerView(
                        offer: offer,
                        onRestore: { DocumentWorkflow.restoreDraft(session) },
                        onDiscard: { DocumentWorkflow.discardDraft(session) }
                    )
                }

                if let preview = session.importPreview {
                    ImportPreviewView(
                        sourceName: preview.sourceName,
                        nodeCount: preview.nodeCount,
                        depth: preview.depth,
                        document: preview.document,
                        onConfirm: { session.loadImported(preview.document) },
                        onCancel: { session.cancelImport() }
                    )
                }
            }
            .toolbar {
                MainToolbar(
                    selectionCount: session.selectedIds.count,
                    canAddChild: canAddChild,
                    canAddSibling: canAddSibling,
                    canDelete: canDelete,
                    canCut: session.canCut,
                    canCopy: session.canCopy,
                    canPaste: session.canPaste,
                    canSetSide: session.canSetSide,
                    zoomPercent: Int((session.camera.scale * 100).rounded()),
                    canvasTool: session.canvasTool,
                    setCanvasTool: { session.canvasTool = $0 },
                    addChild: addChild,
                    addSibling: addSibling,
                    delete: deleteSelected,
                    cut: cutSelection,
                    copy: copySelection,
                    paste: paste,
                    setSideLeft: { setSide(.left) },
                    setSideRight: { setSide(.right) },
                    zoomOut: { zoom(by: 1 / 1.12, viewport: geometry.size) },
                    zoomIn: { zoom(by: 1.12, viewport: geometry.size) },
                    fit: { fit(viewport: geometry.size) },
                    canSetFill: canSetFill,
                    activeFill: fillSelection.common,
                    fillActive: fillSelection.active,
                    setFill: { fill in session.setFill(fill) },
                    exportMarkdown: { DocumentWorkflow.exportMarkdown(session) },
                    exportPNG: { DocumentWorkflow.exportPNG(session) }
                )
            }
        }
        .frame(minWidth: 640, minHeight: 420)
    }

    private var isMulti: Bool { session.selectedIds.count > 1 }

    private var canSetFill: Bool { !session.selectedIds.isEmpty }

    /// 单选/全一致 → active=true，common 为公共 fill（含全 nil）；多选不一致或选中空 → active=false。
    private var fillSelection: (common: NodeFill?, active: Bool) {
        let ids = Array(session.selectedIds)
        guard !ids.isEmpty else { return (nil, false) }
        let first = session.model.node(id: ids[0])?.fill
        let allSame = ids.allSatisfy { session.model.node(id: $0)?.fill == first }
        return (first, allSame)
    }

    private var canAddChild: Bool { !isMulti && session.primarySelectedId != nil }

    private var canAddSibling: Bool {
        guard !isMulti, let id = session.primarySelectedId else { return false }
        return id != session.model.document.root.id
    }

    private var canDelete: Bool {
        session.selectedIds.contains { $0 != session.model.document.root.id }
    }

    private func handleSelection(_ id: UUID?, intent: CanvasSelectIntent) {
        guard let id else {
            session.clearSelection()
            return
        }
        switch intent {
        case .replace:
            session.selectOnly(id)
        case .toggle:
            session.toggleInSelection(id)
        case .range:
            session.selectSiblingRange(to: id)
        }
    }

    private func handleMarqueeSelect(_ ids: Set<UUID>, additive: Bool) {
        let anchor = ids.min { $0.uuidString < $1.uuidString }
        if additive {
            session.replaceSelection(
                session.selectedIds.union(ids),
                anchorId: anchor ?? session.selectionAnchorId
            )
        } else {
            session.replaceSelection(ids, anchorId: anchor)
        }
    }

    private func selectAll() {
        let ids = Set(session.snapshot.frames.keys)
        guard !ids.isEmpty else { return }
        session.replaceSelection(ids, anchorId: session.model.document.root.id)
    }

    /// `/` · `⌘.`：选中集中任一展开则全部折叠，否则全部展开。
    private func toggleCollapseSelection() {
        let targets = session.selectedIds
            .filter { session.model.node(id: $0)?.children.isEmpty == false }
            .sorted { $0.uuidString < $1.uuidString }
        guard !targets.isEmpty else { return }
        let anyExpanded = targets.contains { session.model.node(id: $0)?.collapsed == false }
        session.commandBus.execute(.setCollapsed(ids: targets, collapsed: anyExpanded))
    }

    private func startEditing(_ id: UUID) {
        session.startEditing(id)
    }

    private func toggleCollapse(_ id: UUID) {
        if session.editingId != nil {
            commitEditing()
        }
        session.commandBus.execute(.toggleCollapse(id: id))
    }

    private func commitEditing() {
        if session.commitEditingIfNeeded() {
            requestCanvasFocus()
        }
    }

    private func cancelEditing() {
        session.cancelEditing()
        requestCanvasFocus()
    }

    private func requestCanvasFocus() {
        canvasFocusRequest += 1
    }

    private func addChild() {
        if session.editingId != nil {
            commitEditing()
        }
        guard !isMulti, let selectedId = session.primarySelectedId else { return }
        if session.model.node(id: selectedId)?.collapsed == true {
            session.commandBus.execute(.toggleCollapse(id: selectedId))
        }
        session.commandBus.execute(.addChild(parentId: selectedId, text: "新主题"))
        if let newId = session.primarySelectedId {
            startEditing(newId)
        }
    }

    private func addSibling() {
        if session.editingId != nil {
            commitEditing()
        }
        guard !isMulti,
              let selectedId = session.primarySelectedId,
              selectedId != session.model.document.root.id else {
            return
        }
        session.commandBus.execute(.addSibling(selectedId: selectedId, text: "新主题"))
        if let newId = session.primarySelectedId {
            startEditing(newId)
        }
    }

    private func deleteSelected() {
        if session.editingId != nil {
            commitEditing()
        }
        let ids = Array(session.selectedIds)
        guard ids.contains(where: { $0 != session.model.document.root.id }) else { return }
        session.commandBus.execute(.delete(ids: ids))
    }

    private func move(_ ids: [UUID], to targetId: UUID) {
        if session.editingId != nil { commitEditing() }
        session.move(ids, to: targetId)
    }

    private func setSide(_ side: Side) {
        session.commitEditingIfNeeded()
        session.commandBus.execute(.setSide(ids: Array(session.selectedIds), side: side))
    }

    private func copySelection() {
        if session.editingId != nil { commitEditing() }
        session.copySelection()
    }

    private func cutSelection() {
        if session.editingId != nil { commitEditing() }
        session.cutSelection()
    }

    private func paste() {
        if session.editingId != nil { commitEditing() }
        session.pasteToPrimary()
    }

    private func cancelCut() {
        session.cancelCut()
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
    ContentView(session: DocumentSession())
}
