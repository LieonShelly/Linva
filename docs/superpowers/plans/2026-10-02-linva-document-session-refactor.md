# DocumentSession 职责拆分重构 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 658 行的 `DocumentSession` 门面拆成四个单职责对象（`ContentBlockRules`/`EditingController`/`DocumentPersistence`/`LayoutPipeline`）并立两个协议（`LayoutEngine`/`PersistenceBackend`），对外 API 逐字节不变、行为零回归。

**Architecture:** 保持 `DocumentSession` 的 Facade 角色（对外 @Published 状态 + 用例方法 + `wireCommandBus` 编排不变），把编辑、持久化、布局三个子域抽成独立可测对象，由 Session 组合；聚拢/删空规则抽纯函数（OCP：新块类型=新分支）；持久化与布局立协议（DIP：云同步/多布局换实现）。

**Tech Stack:** Swift 6、Combine（自动保存防抖）、Foundation、Swift Testing；工程 `LinvaApp/`（`PBXFileSystemSynchronizedRootGroup`，新文件放入目录即可被 Xcode 拾取，不改 pbxproj）。

**Spec:** `docs/superpowers/specs/2026-10-02-linva-document-session-refactor-design.md`

## Global Constraints

- **行为零回归**：`DocumentSession` 对外 API（@Published 状态名 + 方法签名 + 错误文案）逐字节不变；壳层（ContentView / CanvasMetalView / SearchBar / LinvaAppApp）零改动。
- **分层白名单**（`scripts/check-boundaries.sh`，构建期强制）：Session 层新文件只 import `Foundation Combine CoreGraphics`；Layout 层新文件只 import `Foundation AppKit CoreGraphics CoreText`。新文件放既有层目录，不新增 import 超白名单模块；`LayoutEngine.swift` 只 import `Foundation`。
- **文档语言**：本仓库所有文档中文优先，专有名词/API 标识符可英文。
- **TDD + 频繁提交**：每步绿可提交，每 Task 独立 `refactor:` commit。
- **改树必须走命令栈**：拆出的对象执行 `commandBus.execute(...)`，不绕过 `CommandBus` 直接改树。
- **命令**（在 `LinvaApp/` 目录下执行）：
  - 全量测试：`xcodebuild test -project LinvaApp.xcodeproj -scheme LinvaApp -destination 'platform=macOS'`
  - 单 suite：`xcodebuild test -project LinvaApp.xcodeproj -scheme LinvaApp -destination 'platform=macOS' -only-testing:LinvaAppTests/<SuiteName>`
  - 边界校验：`./scripts/check-boundaries.sh`

---

### Task 1: 编辑子域拆分（ContentBlockRules + EditingController）

把 `commitEditingIfNeeded` 的聚拢/删空/no-op 规则抽成纯函数 `ContentBlockRules`，编辑会话基线抽成 `EditingController`，`DocumentSession` 的三个编辑方法改为委托。行为零回归。

**Files:**
- Create: `LinvaApp/LinvaApp/Session/ContentBlockRules.swift`
- Create: `LinvaApp/LinvaApp/Session/EditingController.swift`
- Create: `LinvaApp/LinvaAppTests/ContentBlockRulesTests.swift`
- Create: `LinvaApp/LinvaAppTests/EditingControllerTests.swift`
- Modify: `LinvaApp/LinvaApp/Session/DocumentSession.swift`（编辑属性与方法委托）
- Modify: `LinvaApp/LinvaAppTests/DocumentSessionTests.swift`（删除 `SessionConsolidationTests` 套件，迁到 `ContentBlockRulesTests` 直测）

**Interfaces:**
- Consumes: `MindMapModel`（`node(id:)`/`document.root.id`）、`CommandBus`（`execute(_:)`）、`ContentBlock`（`Kind`：`.text(String)`/`.image`）、`ImagePixelSize`、`NodeFrame`、`LayoutSnapshot.frames`。
- Produces:
  - `enum ContentBlockRules` — `enum CoalescingDecision: Equatable { case noChange; case replaceBlocks([ContentBlock]); case deleteNode }`；`static func coalesce(original: [ContentBlock], committedText: String, isRoot: Bool) -> CoalescingDecision`
  - `final class EditingController` — `init(model: MindMapModel, commandBus: CommandBus)`；`private(set) var editingId: UUID?`；`private(set) var originalBlocks: [ContentBlock]`；`private(set) var originalEditingText: String`；`func begin(id: UUID, currentDraft: String, snapshotFrames: [UUID: NodeFrame]) -> Bool`；`@discardableResult func commit(draftText: String) -> Bool`；`func cancel()`

- [ ] **Step 1: 写失败测试 `ContentBlockRulesTests`**

```swift
// LinvaApp/LinvaAppTests/ContentBlockRulesTests.swift
import Foundation
import Testing
@testable import LinvaApp

@Suite("ContentBlockRules")
struct ContentBlockRulesTests {
    private func textBlock(_ s: String) -> ContentBlock {
        ContentBlock(id: UUID(), kind: .text(s))
    }

    private func imageBlock(data: Data, pixelSize: ImagePixelSize) -> ContentBlock {
        ContentBlock(id: UUID(), kind: .image(.init(data: data, pixelSize: pixelSize)))
    }

    private func kinds(_ d: ContentBlockRules.CoalescingDecision) -> [ContentBlock.Kind] {
        switch d {
        case .noChange, .deleteNode: return []
        case .replaceBlocks(let new): return new.map(\.kind)
        }
    }

    private let px = ImagePixelSize(width: 10, height: 10)!

    /// M1-1：首块文 → 文上图下 [text, images]。
    @Test func firstBlockText_textBeforeImages() {
        let d = ContentBlockRules.coalesce(
            original: [textBlock("原文"), imageBlock(data: Data([0x01]), pixelSize: px)],
            committedText: "新文", isRoot: true)
        #expect(kinds(d) == [.text("新文"), .image(.init(data: Data([0x01]), pixelSize: px))])
    }

    /// M1-2：首块图 → 图上文下 [images, text]。
    @Test func firstBlockImage_imageBeforeText() {
        let d = ContentBlockRules.coalesce(
            original: [imageBlock(data: Data([0x01]), pixelSize: px), textBlock("原文")],
            committedText: "新文", isRoot: true)
        #expect(kinds(d) == [.image(.init(data: Data([0x01]), pixelSize: px)), .text("新文")])
    }

    /// M1-3：纯文本 → 退化为 [.text(newText)]。
    @Test func pureText_degradesToSingleTextBlock() {
        let d = ContentBlockRules.coalesce(
            original: [textBlock("原文")], committedText: "纯文本新值", isRoot: true)
        #expect(kinds(d) == [.text("纯文本新值")])
    }

    /// M1-4：全图节点空草稿 → 内容未变（只剩图序列）→ .noChange（不补「未命名」）。
    @Test func allImageNode_emptyDraft_keepsOnlyImages() {
        let d = ContentBlockRules.coalesce(
            original: [imageBlock(data: Data([0x01]), pixelSize: px)], committedText: "", isRoot: true)
        #expect(d == .noChange)
    }

    /// M4：首个非空块判定——空文本块跳过：[.text(""), .image] → 首个非空是图 → 图上文下。
    @Test func emptyFirstTextBlock_isSkipped_imageWins() {
        let d = ContentBlockRules.coalesce(
            original: [textBlock(""), imageBlock(data: Data([0x01]), pixelSize: px)],
            committedText: "新文", isRoot: true)
        #expect(kinds(d) == [.image(.init(data: Data([0x01]), pixelSize: px)), .text("新文")])
    }

    /// 删空：纯文本非根节点 → .deleteNode。
    @Test func pureTextNode_emptyDraft_deletesNode() {
        let d = ContentBlockRules.coalesce(
            original: [textBlock("原文")], committedText: "", isRoot: false)
        #expect(d == .deleteNode)
    }

    /// 删空：纯文本根节点 → 补「未命名」（根不可删）。
    @Test func rootNode_emptyDraft_addsUnnamed() {
        let d = ContentBlockRules.coalesce(
            original: [textBlock("原文")], committedText: "", isRoot: true)
        #expect(kinds(d) == [.text("未命名")])
    }

    /// no-op：内容不变 → .noChange（不入栈）。
    @Test func unchangedText_doesNotChange() {
        let d = ContentBlockRules.coalesce(
            original: [textBlock("原文")], committedText: "原文", isRoot: true)
        #expect(d == .noChange)
    }
}
```

- [ ] **Step 2: 写失败测试 `EditingControllerTests`**

```swift
// LinvaApp/LinvaAppTests/EditingControllerTests.swift
import Foundation
import Testing
@testable import LinvaApp

@Suite("EditingController")
struct EditingControllerTests {
    private func frames(for model: MindMapModel) -> [UUID: NodeFrame] {
        RadialLayout.layout(document: model.document, measure: TextMeasure()).frames
    }

    /// begin → commit 提交聚拢后的 blocks，editingId 回落。
    @Test func begin_commit_updatesBlocksAndClearsEditing() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let controller = EditingController(model: model, commandBus: bus)
        let root = model.document.root.id

        #expect(controller.begin(id: root, currentDraft: "", snapshotFrames: frames(for: model)))
        controller.commit(draftText: "新标题")

        #expect(controller.editingId == nil)
        #expect(model.document.root.text == "新标题")
    }

    /// 无 frame 的节点 begin 失败（编辑静默不启动）。
    @Test func begin_withoutFrame_fails() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let controller = EditingController(model: model, commandBus: bus)
        let ghost = UUID()

        #expect(controller.begin(id: ghost, currentDraft: "", snapshotFrames: [:]) == false)
        #expect(controller.editingId == nil)
    }

    /// 切换编辑目标时先提交旧节点。
    @Test func begin_switchNode_commitsPrevious() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let controller = EditingController(model: model, commandBus: bus)
        let root = model.document.root.id
        let a = model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        let f = frames(for: model)

        #expect(controller.begin(id: root, currentDraft: "", snapshotFrames: f))
        #expect(controller.begin(id: a, currentDraft: "根的新文", snapshotFrames: f))

        #expect(model.document.root.text == "根的新文")  // 旧节点（根）先被提交
        #expect(controller.editingId == a)
    }

    /// cancel 丢弃草稿，树不变。
    @Test func cancel_doesNotMutateTree() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let controller = EditingController(model: model, commandBus: bus)
        let root = model.document.root.id

        controller.begin(id: root, currentDraft: "", snapshotFrames: frames(for: model))
        controller.cancel()

        #expect(controller.editingId == nil)
        #expect(model.document.root.text == "中心主题")
    }
}
```

- [ ] **Step 3: 运行测试确认失败（编译失败，类型不存在）**

Run: `cd LinvaApp && xcodebuild test -project LinvaApp.xcodeproj -scheme LinvaApp -destination 'platform=macOS' -only-testing:LinvaAppTests/ContentBlockRulesTests -only-testing:LinvaAppTests/EditingControllerTests`
Expected: FAIL —— `ContentBlockRules` / `EditingController` / `CoalescingDecision` 未定义。

- [ ] **Step 4: 实现 `ContentBlockRules`**

```swift
// LinvaApp/LinvaApp/Session/ContentBlockRules.swift
import Foundation

/// 编辑提交时的内容块聚拢规则（SRP/OCP：新块类型加一个分支，不改 Session）。
enum ContentBlockRules {
    /// 提交决策：不改 / 整块替换 / 删除节点。
    enum CoalescingDecision: Equatable {
        case noChange
        case replaceBlocks([ContentBlock])
        case deleteNode
    }

    /// 对编辑提交做聚拢。语义与历史 DocumentSession.commitEditingIfNeeded 逐字节一致：
    /// 文本合并单块；图片按原相对顺序聚拢单侧（首个非空块是图 → 图上文下，否则文上图下）。
    /// 删空：有图只留图 / 纯文本非根删节点 / 根补「未命名」。
    /// no-op 按内容（忽略块 id）比较，内容不变 → .noChange 不入栈。
    static func coalesce(
        original: [ContentBlock],
        committedText: String,
        isRoot: Bool
    ) -> CoalescingDecision {
        let text = committedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = original.filter { block in
            if case .image = block.kind { return true } else { return false }
        }
        let firstBlockIsImage: Bool = {
            for block in original {
                switch block.kind {
                case .text(let s):
                    if !s.isEmpty { return false }   // 首个非空块是文本 → 文上图下
                case .image:
                    return true                      // 首个非空块是图片 → 图上文下
                }
            }
            return false   // 全空文本块 / 无块 → 文本在前默认
        }()
        var newBlocks: [ContentBlock]
        if text.isEmpty {
            if !images.isEmpty {
                newBlocks = images
            } else if !isRoot {
                return .deleteNode
            } else {
                newBlocks = [ContentBlock(id: UUID(), kind: .text("未命名"))]
            }
        } else if firstBlockIsImage {
            newBlocks = images + [ContentBlock(id: UUID(), kind: .text(text))]
        } else {
            newBlocks = [ContentBlock(id: UUID(), kind: .text(text))] + images
        }
        if newBlocks.map(\.kind) != original.map(\.kind) {
            return .replaceBlocks(newBlocks)
        }
        return .noChange
    }
}
```

- [ ] **Step 5: 实现 `EditingController`**

```swift
// LinvaApp/LinvaApp/Session/EditingController.swift
import Foundation

/// 编辑会话控制器（SRP：编辑草稿态的基线记录 + 提交/取消编排）。
/// 对外 draftText 仍由 DocumentSession 持有（CommitTextView 双向绑定），本对象只持内部基线。
final class EditingController {
    private let model: MindMapModel
    private let commandBus: CommandBus

    private(set) var editingId: UUID?
    private(set) var originalBlocks: [ContentBlock] = []
    private(set) var originalEditingText = ""

    init(model: MindMapModel, commandBus: CommandBus) {
        self.model = model
        self.commandBus = commandBus
    }

    /// 开始编辑。节点须存在且已布局（有 frame）；若正编辑另一节点，先提交旧节点。
    /// - Parameters:
    ///   - id: 目标节点
    ///   - currentDraft: DocumentSession 当前草稿（切换节点时用于提交旧节点）
    ///   - snapshotFrames: 当前布局帧表（无 frame 的节点静默不启动编辑）
    /// - Returns: 是否开始编辑
    func begin(id: UUID, currentDraft: String, snapshotFrames: [UUID: NodeFrame]) -> Bool {
        guard model.node(id: id) != nil, snapshotFrames[id] != nil else { return false }
        if editingId != nil, editingId != id {
            _ = commit(draftText: currentDraft)
        }
        guard let node = model.node(id: id) else { return false }
        editingId = id
        originalEditingText = node.text
        originalBlocks = node.blocks
        return true
    }

    /// 提交编辑：聚拢 → 落命令栈。返回是否有进行中的编辑（无论是否入栈）。
    @discardableResult
    func commit(draftText: String) -> Bool {
        guard let editingId else { return false }
        let isRoot = editingId == model.document.root.id
        let decision = ContentBlockRules.coalesce(
            original: originalBlocks,
            committedText: draftText,
            isRoot: isRoot
        )
        switch decision {
        case .noChange:
            break
        case .replaceBlocks(let new):
            commandBus.execute(.setBlocks(id: editingId, old: originalBlocks, new: new))
        case .deleteNode:
            commandBus.execute(.delete(ids: [editingId]))
        }
        self.editingId = nil
        originalBlocks = []
        originalEditingText = ""
        return true
    }

    /// 取消编辑：丢弃草稿改动，仅清基线。
    func cancel() {
        editingId = nil
        originalBlocks = []
        originalEditingText = ""
    }
}
```

- [ ] **Step 6: 改 `DocumentSession` 编辑方法为委托**

在 `DocumentSession.swift`：

（1）删除两个私有属性 `private var originalEditingText = ""` 与 `private var originalBlocks: [ContentBlock] = []`。

（2）新增私有属性并在 `init` 创建：
```swift
    private let editingController: EditingController
```
在 `init` 内 `self.snapshot = LayoutSnapshot(frames: [:], edges: [])` 之前加：
```swift
        self.editingController = EditingController(model: model, commandBus: commandBus)
```

（3）替换 `startEditing(_:)` 整个方法体：
```swift
    func startEditing(_ id: UUID) {
        guard editingController.begin(id: id, currentDraft: draftText, snapshotFrames: snapshot.frames) else { return }
        selectOnly(id)
        draftText = editingController.originalEditingText
        editingId = id
    }
```

（4）替换 `commitEditingIfNeeded()` 整个方法体（原 50 行 if/else 链删除，规则逻辑已在 `ContentBlockRules`）：
```swift
    @discardableResult
    func commitEditingIfNeeded() -> Bool {
        guard editingId != nil else { return false }
        editingController.commit(draftText: draftText)
        editingId = nil
        draftText = ""
        return true
    }
```

（5）替换 `cancelEditing()`：
```swift
    func cancelEditing() {
        draftText = editingController.originalEditingText
        editingController.cancel()
        editingId = nil
    }
```

（6）在 `newDocument`/`loadImported`/`load`/`restore` 四个方法内，把编辑重置行 `editingId = nil; draftText = ""; originalBlocks = []; originalEditingText = ""` 替换为：
```swift
        editingId = nil
        draftText = ""
        editingController.cancel()
```

- [ ] **Step 7: 删除 `DocumentSessionTests` 里的 `SessionConsolidationTests` 套件**

在 `LinvaApp/LinvaAppTests/DocumentSessionTests.swift` 中，删除 `@Suite("Session 聚拢规则") struct SessionConsolidationTests { … }` 整个块（约 697-770 行附近，含 M1-M4 与 `commit(_:nodeId:draft:)` helper）——其断言已由 `ContentBlockRulesTests` 直测覆盖。其余 `@Suite`（DocumentSession / Import / Autosave / Recovery / Session 图片）保留不动。

- [ ] **Step 8: 跑测试验证全绿**

Run: `cd LinvaApp && xcodebuild test -project LinvaApp.xcodeproj -scheme LinvaApp -destination 'platform=macOS'`
Expected: PASS —— 全部测试（含新 `ContentBlockRulesTests`/`EditingControllerTests`，不含已删的 SessionConsolidationTests）通过；行为零回归。

- [ ] **Step 9: Commit**

```bash
git add LinvaApp/LinvaApp/Session/ContentBlockRules.swift \
  LinvaApp/LinvaApp/Session/EditingController.swift \
  LinvaApp/LinvaApp/Session/DocumentSession.swift \
  LinvaApp/LinvaAppTests/ContentBlockRulesTests.swift \
  LinvaApp/LinvaAppTests/EditingControllerTests.swift \
  LinvaApp/LinvaAppTests/DocumentSessionTests.swift
git commit -m "refactor: 编辑子域拆分——ContentBlockRules 纯函数 + EditingController 会话，Session 委托"
```

---

### Task 2: 持久化子域拆分（DocumentPersistence + PersistenceBackend + adopt 模板）

把文件 I/O、脏判定、自动保存、崩溃恢复抽成 `DocumentPersistence`；`PersistenceBackend` 协议抽象字节读写（云同步接缝）；`adopt` 模板消除 `newDocument`/`load`/`loadImported`/`restore` 的重复状态重置。

**Files:**
- Create: `LinvaApp/LinvaApp/Session/PersistenceBackend.swift`（`PersistenceBackend` 协议 + `LinvaFilePersistence` + 从 DocumentSession.swift 迁入 `SecurityScopedAccess`）
- Create: `LinvaApp/LinvaApp/Session/DocumentPersistence.swift`
- Create: `LinvaApp/LinvaAppTests/DocumentPersistenceTests.swift`
- Modify: `LinvaApp/LinvaApp/Session/DocumentSession.swift`（生命周期方法委托 + `isDirty`/`fileURL`/`documentID`/`recovery` 镜像）
- Modify: `LinvaApp/LinvaAppTests/DocumentSessionTests.swift`（Autosave/Recovery/Import 套件保留为全链冒烟，不删）

**Interfaces:**
- Consumes: `LinvaCodec`（`encode(_:)`/`decode(_:)`）、`AutosaveStore`（`write/delete/latestPending/clearAll/load`）、`AutosaveMeta`、`RecoveryOffer`、`MindMapDocument`、`DocumentSessionError.noFileURL`。
- Produces:
  - `protocol PersistenceBackend { func readData(from url: URL) throws -> Data; func writeData(_ data: Data, to url: URL) throws }`
  - `final class LinvaFilePersistence: PersistenceBackend`（纯字节，`Data(contentsOf:)`/`write(options: .atomic)`）
  - `final class DocumentPersistence` — `init(backend: PersistenceBackend = LinvaFilePersistence(), securityScopedAccess: SecurityScopedAccess = SecurityScopedAccess(), autosaveStore: AutosaveStore = AutosaveStore())`；`private(set) var fileURL: URL?`；`private(set) var lastSavedDocument: MindMapDocument`；`private(set) var documentID: UUID`；`private(set) var isDirty: Bool`；`private(set) var recovery: RecoveryOffer?`；`func adopt(document:fileURL:isDirty:keepLastSaved:regenerateID:clearRecovery:)`；`func noteChange(current: MindMapDocument) -> Bool`；`func load(from url: URL) throws -> MindMapDocument`；`func save(document: MindMapDocument) throws`；`func saveAs(document: MindMapDocument, to url: URL) throws`；`func scheduleAutoSave(document: @escaping () -> MindMapDocument, changeCount: @escaping () -> Int)`；`func flushAutoSave(document: MindMapDocument, changeCount: Int)`；`@discardableResult func scanForRecovery() -> RecoveryOffer?`；`func restore(draftFrom offer: RecoveryOffer) throws -> MindMapDocument`；`func discardDraft() throws`

- [ ] **Step 1: 写失败测试 `DocumentPersistenceTests`**

```swift
// LinvaApp/LinvaAppTests/DocumentPersistenceTests.swift
import Foundation
import Testing
@testable import LinvaApp

@Suite("DocumentPersistence")
struct DocumentPersistenceTests {
    private func tempURL(_ name: String) throws -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString).linva")
    }

    /// round-trip：saveAs → 新 persistence load 回，内容一致、isDirty=false。
    @Test func saveAs_load_roundTrip() throws {
        let persistence = DocumentPersistence()
        let url = try tempURL("rt")
        var doc = MindMapDocument.blank(rootText: "根")
        doc.root.children = [Node(text: "子")]
        try persistence.saveAs(document: doc, to: url)

        let loaded = DocumentPersistence()
        let read = try loaded.load(from: url)
        #expect(read.root.text == "根")
        #expect(read.root.children.count == 1)
        #expect(loaded.isDirty == false)
        #expect(loaded.fileURL == url)
    }

    /// save 无 fileURL → 抛 noFileURL。
    @Test func save_withoutFileURL_throws() {
        let persistence = DocumentPersistence()
        let doc = MindMapDocument.blank()
        #expect(throws: DocumentSessionError.noFileURL) {
            try persistence.save(document: doc)
        }
    }

    /// noteChange：文档变化 → true（脏），还原到 lastSaved → false（干净）。
    @Test func noteChange_tracksDirtyState() throws {
        let persistence = DocumentPersistence()
        let url = try tempURL("dirty")
        var doc = MindMapDocument.blank(rootText: "根")
        try persistence.saveAs(document: doc, to: url)

        doc.root.children = [Node(text: "x")]
        #expect(persistence.noteChange(current: doc) == true)

        doc.root.children = []
        #expect(persistence.noteChange(current: doc) == false)
    }

    /// adopt keepLastSaved=true：导入/恢复语义——lastSaved 保持旧值，撤销回载入态 isDirty 仍 true。
    @Test func adopt_keepLastSaved_preservesLastSaved() {
        let persistence = DocumentPersistence()
        let original = MindMapDocument.blank(rootText: "原始")
        persistence.adopt(document: original, fileURL: nil, isDirty: false,
                          keepLastSaved: false, regenerateID: true)

        var imported = MindMapDocument.blank(rootText: "导入")
        imported.root.children = [Node(text: "a")]
        persistence.adopt(document: imported, fileURL: nil, isDirty: true,
                          keepLastSaved: true, regenerateID: true)

        // lastSaved 仍是 original → 撤销回导入前的 isDirty 仍 true
        #expect(persistence.noteChange(current: original) == true)
    }

    /// restore 返回副本并保留 documentID；副本加载的 URL 恢复为 originalURL。
    @Test func restore_loadsDraft_returnsDocument() throws {
        let dir = try FileManager.default.url(for: .itemReplacementDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AutosaveStore(directory: dir)
        let persistence = DocumentPersistence(autosaveStore: store)

        var draft = MindMapDocument.blank(rootText: "草稿根")
        draft.root.children = [Node(text: "恢复内容")]
        let meta = AutosaveMeta(documentID: UUID(), originalURL: nil,
                                savedAt: Date(), changeCount: 1, rootText: "草稿根")
        try store.write(document: draft, meta: meta)
        let offer = RecoveryOffer(meta: meta)

        let restored = try persistence.restore(draftFrom: offer)
        #expect(restored.root.text == "草稿根")
        #expect(restored.root.children[0].text == "恢复内容")
        #expect(persistence.isDirty == true)
    }
}
```

> 注：`DocumentSessionError` 需 `Equatable` 才能在 `#expect(throws:)` 用——已是 `enum DocumentSessionError: Error, Equatable`。

- [ ] **Step 2: 运行测试确认失败（类型不存在）**

Run: `cd LinvaApp && xcodebuild test -project LinvaApp.xcodeproj -scheme LinvaApp -destination 'platform=macOS' -only-testing:LinvaAppTests/DocumentPersistenceTests`
Expected: FAIL —— `DocumentPersistence` / `PersistenceBackend` 未定义。

- [ ] **Step 3: 实现 `PersistenceBackend.swift`**

```swift
// LinvaApp/LinvaApp/Session/PersistenceBackend.swift
import Foundation

/// 持久化后端抽象（DIP）：读写字节。未来云同步实现同一协议，本地 scope 语义由 DocumentPersistence 处理。
protocol PersistenceBackend {
    func readData(from url: URL) throws -> Data
    func writeData(_ data: Data, to url: URL) throws
}

/// 本地文件持久化：纯字节读写（原子写）。
final class LinvaFilePersistence: PersistenceBackend {
    func readData(from url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func writeData(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }
}

/// 沙盒安全作用域读写封装（start/stop 平衡，持有当前 URL 的 scope）。原样迁自 DocumentSession.swift。
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
```

- [ ] **Step 4: 实现 `DocumentPersistence.swift`**

```swift
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
        try securityScopedAccess.replace(with: url) {
            let data = try backend.readData(from: url)
            return try LinvaCodec.decode(data)
        }
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
        return doc
    }

    func discardDraft() throws {
        isDirty = false
        recovery = nil
        try autosaveStore.clearAll()
        documentID = UUID()
    }
}
```

- [ ] **Step 5: 从 `DocumentSession.swift` 移除 `SecurityScopedAccess` 类定义**

删除 `DocumentSession.swift` 顶部 `final class SecurityScopedAccess { … }` 整个块（约 14-75 行）——已迁至 `PersistenceBackend.swift` Step 3。删除后 `DocumentSession` 不再直接引用它。

- [ ] **Step 6: 改 `DocumentSession` 生命周期方法为委托 + 镜像**

在 `DocumentSession.swift`：

（1）删除私有属性 `private let securityScopedAccess: SecurityScopedAccess`、`private let autosaveStore: AutosaveStore`、`private var autoSaveDebounce: AnyCancellable?`、`private var lastSavedDocument: MindMapDocument`；删除 `@Published var fileURL`、`@Published var isDirty = false`、`var documentID = UUID()`、`@Published var recovery: RecoveryOffer?` 这些属性的 **定义**（改为镜像 computed 或保留 @Published 由方法赋值——见下）。

> 为保证对外 API（@Published 属性名）不变，`fileURL`/`isDirty`/`recovery` 仍保留为 `@Published var` 但改为由 Session 方法同步；`documentID` 保留为 `var`（非 @Published，现状即是）。**做法：保留这 4 个属性声明不动**，仅删除 `lastSavedDocument`/`autoSaveDebounce`/`securityScopedAccess`/`autosaveStore` 私有字段。

新增私有属性：
```swift
    private let persistence: DocumentPersistence
```

（2）替换 `init` 签名与体：
```swift
    init(
        model: MindMapModel? = nil,
        measure: TextMeasure = TextMeasure(),
        autosaveStore: AutosaveStore = AutosaveStore(),
        securityScopedAccess: SecurityScopedAccess = SecurityScopedAccess()
    ) {
        let model = model ?? MindMapModel.makeNew()
        self.model = model
        self.commandBus = CommandBus(model: model)
        self.measure = measure
        self.persistence = DocumentPersistence(
            backend: LinvaFilePersistence(),
            securityScopedAccess: securityScopedAccess,
            autosaveStore: autosaveStore
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
    }
```
（保留 `autosaveStore`/`securityScopedAccess` 参数兼容现有测试与调用；`LayoutPipeline` 注入在 Task 3 加。）

（3）替换 `newDocument`：
```swift
    func newDocument() {
        commitEditingIfNeeded()
        let doc = MindMapDocument.blank()
        model.document = doc
        persistence.adopt(document: doc, fileURL: nil, isDirty: false,
                          keepLastSaved: false, regenerateID: true)
        resetSessionState(selecting: doc.root.id)
    }
```

（4）替换 `loadImported`：
```swift
    func loadImported(_ document: MindMapDocument) {
        commitEditingIfNeeded()
        model.document = document
        // keepLastSaved: true —— 导入文档无磁盘文件，撤销回载入态 isDirty 仍 true。
        persistence.adopt(document: document, fileURL: nil, isDirty: true,
                          keepLastSaved: true, regenerateID: true)
        resetSessionState(selecting: document.root.id)
    }
```

（5）替换 `load`：
```swift
    func load(from url: URL) throws {
        commitEditingIfNeeded()
        let doc = try persistence.load(from: url)
        model.document = doc
        persistence.adopt(document: doc, fileURL: url, isDirty: false,
                          keepLastSaved: false, regenerateID: true)
        resetSessionState(selecting: doc.root.id)
    }
```

（6）替换 `save`：
```swift
    func save() throws {
        commitEditingIfNeeded()
        try persistence.save(document: model.document)
        isDirty = persistence.isDirty
    }
```

（7）替换 `saveAs`：
```swift
    func saveAs(to url: URL) throws {
        commitEditingIfNeeded()
        try persistence.saveAs(document: model.document, to: url)
        fileURL = persistence.fileURL
        isDirty = persistence.isDirty
    }
```

（8）替换 `restore`：
```swift
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
```

（9）替换 `discardDraft`：
```swift
    func discardDraft() throws {
        try persistence.discardDraft()
        isDirty = persistence.isDirty
        commandBus.clearHistory()
        undoRevision += 1
    }
```

（10）替换 `scanForRecovery`：
```swift
    @discardableResult
    func scanForRecovery() -> RecoveryOffer? {
        let offer = persistence.scanForRecovery()
        recovery = persistence.recovery
        return offer
    }
```

（11）替换 `flushAutoSave`：
```swift
    func flushAutoSave() {
        persistence.flushAutoSave(document: model.document, changeCount: undoRevision)
    }
```

（12）替换 `markDirtyAndRelayout`：
```swift
    func markDirtyAndRelayout() {
        isDirty = persistence.noteChange(current: model.document)
        relayout()
    }
```

（13）替换 `wireCommandBus` 的 `scheduleAutoSave()` 调用：
```swift
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
```
删除旧的 `scheduleAutoSave()` 与 `hasLoadedEditableContent`/`pendingChangeCount` 私有方法（已迁至 persistence）。

（14）新增 `resetSessionState` 私有方法（消除 5 处重复的会话侧重置；末尾统一 relayout）：
```swift
    /// 会话侧状态重置（adopt 已处理持久化态）：选中根、清命令栈、编辑/相机/导入预览/错误清空、重布局。
    private func resetSessionState(selecting rootId: UUID) {
        model.selectOnly(rootId)
        syncSelectionFromModel()
        commandBus.clearHistory()
        undoRevision += 1
        selectedImageBlock = nil
        editingId = nil
        draftText = ""
        editingController.cancel()
        camera = Camera()
        importPreview = nil
        errorMessage = nil
        relayout()
    }
```

> 注意：`resetSessionState` 内 `recovery` 清空已由 `persistence.adopt(clearRecovery:true)`（默认）处理，故此处不再显式 `recovery = nil`；但 `scanForRecovery` 赋值 `recovery = persistence.recovery` 保持镜像。

- [ ] **Step 7: 跑测试验证全绿**

Run: `cd LinvaApp && xcodebuild test -project LinvaApp.xcodeproj -scheme LinvaApp -destination 'platform=macOS'`
Expected: PASS —— 现有 DocumentSession/Autosave/Recovery/Import 套件 + 新 `DocumentPersistenceTests` 全绿；行为零回归。

- [ ] **Step 8: Commit**

```bash
git add LinvaApp/LinvaApp/Session/PersistenceBackend.swift \
  LinvaApp/LinvaApp/Session/DocumentPersistence.swift \
  LinvaApp/LinvaApp/Session/DocumentSession.swift \
  LinvaApp/LinvaAppTests/DocumentPersistenceTests.swift
git commit -m "refactor: 持久化子域拆分——DocumentPersistence + PersistenceBackend 协议 + adopt 模板消重复"
```

---

### Task 3: 布局子域拆分（LayoutPipeline + LayoutEngine 协议）

`RadialLayout` 已 conform `LayoutEngine`（协议静态方法签名一致，空 extension 即 conform）；`LayoutPipeline` 持布局引擎类型与量字器，`DocumentSession.relayout` 委托。

**Files:**
- Create: `LinvaApp/LinvaApp/Layout/LayoutEngine.swift`
- Create: `LinvaApp/LinvaApp/Session/LayoutPipeline.swift`
- Create: `LinvaApp/LinvaAppTests/LayoutPipelineTests.swift`
- Modify: `LinvaApp/LinvaApp/Session/DocumentSession.swift`（`relayout` 委托 + init 注入 layoutPipeline）

**Interfaces:**
- Consumes: `MindMapDocument`、`TextMeasure`、`LayoutSnapshot`、`RadialLayout.layout(document:measure:)`。
- Produces:
  - `protocol LayoutEngine { static func layout(document: MindMapDocument, measure: TextMeasure) -> LayoutSnapshot }`
  - `extension RadialLayout: LayoutEngine {}`（空 conform，签名已一致）
  - `final class LayoutPipeline` — `init(layoutEngineType: LayoutEngine.Type = RadialLayout.self, measure: TextMeasure = TextMeasure())`；`func relayout(document: MindMapDocument) -> LayoutSnapshot`

- [ ] **Step 1: 写失败测试 `LayoutPipelineTests`**

```swift
// LinvaApp/LinvaAppTests/LayoutPipelineTests.swift
import Foundation
import Testing
@testable import LinvaApp

/// 用于验证 LayoutPipeline 换引擎的假实现。
struct FakeLayoutEngine: LayoutEngine {
    static func layout(document: MindMapDocument, measure: TextMeasure) -> LayoutSnapshot {
        LayoutSnapshot(frames: [:], edges: [])
    }
}

@Suite("LayoutPipeline")
struct LayoutPipelineTests {
    /// 默认引擎 = RadialLayout：产出与直接调用 RadialLayout.layout 的帧数一致。
    @Test func defaultUsesRadialLayout() {
        let pipeline = LayoutPipeline()
        let doc = MindMapDocument.blank()
        let snap = pipeline.relayout(document: doc)
        let expected = RadialLayout.layout(document: doc, measure: TextMeasure())
        #expect(snap.frames.count == expected.frames.count)
    }

    /// 注入假引擎 → 换布局不碰 Session。
    @Test func injectedEngine_isUsed() {
        let pipeline = LayoutPipeline(layoutEngineType: FakeLayoutEngine.self)
        let snap = pipeline.relayout(document: MindMapDocument.blank())
        #expect(snap.frames.isEmpty)
    }
}
```

- [ ] **Step 2: 运行测试确认失败（类型不存在）**

Run: `cd LinvaApp && xcodebuild test -project LinvaApp.xcodeproj -scheme LinvaApp -destination 'platform=macOS' -only-testing:LinvaAppTests/LayoutPipelineTests`
Expected: FAIL —— `LayoutEngine` / `LayoutPipeline` 未定义。

- [ ] **Step 3: 实现 `LayoutEngine.swift`**

```swift
// LinvaApp/LinvaApp/Layout/LayoutEngine.swift
import Foundation

/// 布局引擎抽象（DIP）：加第二种布局（组织图等）时替换类型。协议静态方法，RadialLayout 已具同签名。
protocol LayoutEngine {
    static func layout(document: MindMapDocument, measure: TextMeasure) -> LayoutSnapshot
}
```

- [ ] **Step 4: 实现 `LayoutPipeline.swift`**

```swift
// LinvaApp/LinvaApp/Session/LayoutPipeline.swift
import Foundation

/// 布局子域（SRP）：持量字器 + 布局引擎类型，产出 LayoutSnapshot。
final class LayoutPipeline {
    private let layoutEngineType: LayoutEngine.Type
    private let measure: TextMeasure

    init(layoutEngineType: LayoutEngine.Type = RadialLayout.self, measure: TextMeasure = TextMeasure()) {
        self.layoutEngineType = layoutEngineType
        self.measure = measure
    }

    func relayout(document: MindMapDocument) -> LayoutSnapshot {
        layoutEngineType.layout(document: document, measure: measure)
    }
}
```

- [ ] **Step 5: `RadialLayout` conform `LayoutEngine`**

在 `RadialLayout.swift` 文件底部追加：
```swift
extension RadialLayout: LayoutEngine {}
```
（`RadialLayout` 已是 `enum` + `static func layout(document:measure:) -> LayoutSnapshot`，签名与协议一致，空 extension 即 conform；确认 `layout` 的返回类型确实是 `LayoutSnapshot`，若签名不完全一致则补显式转发实现。）

- [ ] **Step 6: 改 `DocumentSession` 的 `relayout` 委托 + init 注入**

在 `DocumentSession.swift`：

（1）新增私有属性：
```swift
    private let layoutPipeline: LayoutPipeline
```

（2）`init` 增参数并在体内赋值：
```swift
    init(
        model: MindMapModel? = nil,
        measure: TextMeasure = TextMeasure(),
        layoutPipeline: LayoutPipeline = LayoutPipeline(),
        autosaveStore: AutosaveStore = AutosaveStore(),
        securityScopedAccess: SecurityScopedAccess = SecurityScopedAccess()
    ) {
        let model = model ?? MindMapModel.makeNew()
        self.model = model
        self.commandBus = CommandBus(model: model)
        self.measure = measure
        self.layoutPipeline = layoutPipeline
        self.persistence = DocumentPersistence(
            backend: LinvaFilePersistence(),
            securityScopedAccess: securityScopedAccess,
            autosaveStore: autosaveStore
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
    }
```

（3）替换 `relayout()`：
```swift
    func relayout() {
        snapshot = layoutPipeline.relayout(document: model.document)
    }
```

（4）删除不再使用的私有属性 `private let measure: TextMeasure`（已由 `LayoutPipeline` 持有）——若 `measure` 仍被别处引用则保留；经 grep 确认 `measure` 仅 `relayout` 使用。

- [ ] **Step 7: 跑测试验证全绿**

Run: `cd LinvaApp && xcodebuild test -project LinvaApp.xcodeproj -scheme LinvaApp -destination 'platform=macOS'`
Expected: PASS —— 全绿 + `LayoutPipelineTests` 通过；行为零回归。

- [ ] **Step 8: Commit**

```bash
git add LinvaApp/LinvaApp/Layout/LayoutEngine.swift \
  LinvaApp/LinvaApp/Layout/RadialLayout.swift \
  LinvaApp/LinvaApp/Session/LayoutPipeline.swift \
  LinvaApp/LinvaApp/Session/DocumentSession.swift \
  LinvaApp/LinvaAppTests/LayoutPipelineTests.swift
git commit -m "refactor: 布局子域拆分——LayoutPipeline + LayoutEngine 协议，relayout 委托"
```

---

### Task 4: Session 门面瘦身收尾（镜像 + 转发 + 编排）

`DocumentSession` 已组合 `editingController`/`persistence`/`layoutPipeline`，本 Task 清点并删减 Session 内已迁出的冗余，确保只留 @Published 镜像、用例转发、`wireCommandBus` 编排；行数从 658 → ~280。

**Files:**
- Modify: `LinvaApp/LinvaApp/Session/DocumentSession.swift`

**Interfaces:**
- Consumes: Task 1-3 的 `editingController`/`persistence`/`layoutPipeline`。
- Produces: 纯门面 `DocumentSession`（对外 API 不变）。

- [ ] **Step 1: 核对残留引用并清理**

在 `DocumentSession.swift` 内 grep 确认以下已迁出字段/方法无残留引用，存在则删除：
- `lastSavedDocument`（已迁 persistence）
- `autoSaveDebounce` / `scheduleAutoSave()` / `hasLoadedEditableContent` / `pendingChangeCount`（已迁 persistence）
- `measure`（已迁 layoutPipeline）
- `securityScopedAccess` / `autosaveStore`（已迁 persistence）

保留：`@Published var fileURL`/`isDirty`/`recovery`、`var documentID`、`@Published var snapshot`/`camera`/`canvasTool`/`errorMessage`、`editingId`/`draftText`、`selectedIds`/`selectionAnchorId`、`clipboard`/`cutSourceIds`/`selectedImageBlock`/`search`/`importPreview`、`imageNormalizer`。

- [ ] **Step 2: 确认 Session 剩余成员清单（门面形态）**

确认 `DocumentSession.swift` 现有成员只含：
- **组合**：`model`/`commandBus`/`editingController`/`persistence`/`layoutPipeline`
- **@Published 镜像**：见 Step 1 保留清单
- **选中/搜索/剪贴板/相机/图片块**：`selectOnly`/`toggleInSelection`/`selectSiblingRange`/`replaceSelection`/`clearSelection`/`syncSelectionFromModel`/`copySelection`/`cutSelection`/`cancelCut`/`pasteToPrimary`/`canCopy`/`canCut`/`canPaste`/`runSearch`/`openSearch`/`closeSearch`/`revealSearchMatch`/`centerCamera`/`selectImageBlock`/`clearImageSelection`/`removeSelectedImageBlock`/`appendPastedImage`
- **用例转发**：`move`/`setFill`/`canSetSide`/`prepareReplace`/`markDirtyAndRelayout`/`clearError`
- **生命周期委托**：`newDocument`/`load`/`save`/`saveAs`/`loadImported`/`restore`/`discardDraft`/`scanForRecovery`/`flushAutoSave`/`cancelImport`
- **编辑委托**：`startEditing`/`commitEditingIfNeeded`/`cancelEditing`
- **编排**：`wireCommandBus`/`resetSessionState`
- **computed**：`primarySelectedId`/`windowTitle`

任何不属于以上清单的成员，若已无引用则删除。

- [ ] **Step 3: 验证行数与测试**

Run: `cd LinvaApp && wc -l LinvaApp/LinvaApp/Session/DocumentSession.swift`
Expected: `<= 320` 行。

Run: `cd LinvaApp && xcodebuild test -project LinvaApp.xcodeproj -scheme LinvaApp -destination 'platform=macOS'`
Expected: PASS —— 全绿，行为零回归。

- [ ] **Step 4: Commit**

```bash
git add LinvaApp/LinvaApp/Session/DocumentSession.swift
git commit -m "refactor: Session 门面瘦身——只留 @Published 镜像 + 用例转发 + 编排（658→~280 行）"
```

---

### Task 5: 边界脚本 + 架构现状落档

确认新文件不越层（白名单），并更新架构现状文档反映拆分后的 Session 层。

**Files:**
- Verify: `scripts/check-boundaries.sh`（预期无需改白名单，但需跑通）
- Modify: `docs/架构现状.md`（§2 Session 层模块、§2.1 代码量、§5 白名单确认、§8.4 薄弱点 1 状态、§9 演进顺序）

**Interfaces:**
- Consumes: 全部分拆产物。

- [ ] **Step 1: 跑边界校验**

Run: `./scripts/check-boundaries.sh`
Expected: 退出码 0。若报违规：`LayoutEngine.swift`（Layout 层）只应 import `Foundation`；`ContentBlockRules`/`EditingController`/`DocumentPersistence`/`LayoutPipeline`/`PersistenceBackend`（Session 层）只应 import `Foundation Combine CoreGraphics`。新文件在既有层目录，规则按目录自动适用，通常无需改白名单；若新增了超白名单的 import，把该目录白名单补上对应模块（与 `docs/架构现状.md` §5 同步）。

- [ ] **Step 2: 更新 `docs/架构现状.md`**

（1）§2 Session 层：模块列表由 `DocumentSession`/`Camera`/`DropIntent`/`Clipboard`/`AutosaveStore` 增补 `ContentBlockRules`/`EditingController`/`DocumentPersistence`/`PersistenceBackend`/`LayoutPipeline`；Layout 层增补 `LayoutEngine`。

（2）§2.1 代码量：Session 文件数与行数更新（DocumentSession 658 → ~280，新增 5 文件）。

（3）§5 白名单：确认 Session 层新增文件仍 `Foundation Combine CoreGraphics`；Layout 层新增 `LayoutEngine` 仅 `Foundation`（不超现有 `Foundation AppKit CoreGraphics CoreText`）。

（4）§8.4 薄弱点 1：状态改为「已拆——DocumentSession 门面瘦身，编辑/持久化/布局子域独立可测，立 LayoutEngine/PersistenceBackend 协议」；建议栏更新为「新块类型走 ContentBlockRules 分支；多布局替换 LayoutEngine；云同步实现 PersistenceBackend」。

（5）§9 演进顺序：标记「短线 Session 内部拆用例 API」为已落地。

（6）§10/§11 相关描述同步（Session 门面职责表述）。

- [ ] **Step 3: 全量验证**

Run: `cd LinvaApp && xcodebuild test -project LinvaApp.xcodeproj -scheme LinvaApp -destination 'platform=macOS'`
Expected: PASS 全绿。再跑 `./scripts/check-boundaries.sh` 退出码 0。

- [ ] **Step 4: Commit**

```bash
git add scripts/check-boundaries.sh docs/架构现状.md
git commit -m "docs: 架构现状落档——Session 拆分产物与 LayoutEngine/PersistenceBackend 协议"
```

---

## Self-Review

**1. Spec coverage（对照 spec 各节）：**
- 目标 1（Session 658→~280）：Task 4 ✓
- 目标 2（每对象独立单测 + 聚拢直测）：Task 1-3 各建 suite，`ContentBlockRulesTests` 直测 ✓
- 目标 3（对外 API 不变 / 行为零回归）：每 Task 全量测试绿 + 壳层零改动 ✓
- 目标 4（LayoutEngine + PersistenceBackend 协议）：Task 3 / Task 2 ✓
- §4 组件架构对象表：Task 1-3 逐一实现 ✓
- §5.1 编排顺序不变：Task 2 (13) wireCommandBus 顺序保留 ✓
- §5.2 聚拢三态：ContentBlockRules ✓
- §5.3 adopt 模板 / keepLastSaved 语义：Task 2 (4)/(6) ✓
- §6 错误与边界：`DocumentSessionError.noFileURL` 保留；Task 5 白名单 ✓
- §7 测试策略：搬迁直测 + 保留全链冒烟 ✓
- §8 迁移顺序 Step 1-5：Task 1-5 一一对应 ✓

**2. Placeholder scan：** 无 TBD/TODO/「实现适当错误处理」等；每步含完整代码或精确修改指令。Task 3 Step 5 的 RadialLayout conform 有「若签名不完全一致则补转发」的兜底判断（因 grep 只确认了 `static func layout(` 前缀，未确认完整签名），属合理的实现期校验，非占位符。

**3. Type consistency：**
- `ContentBlockRules.coalesce(original:committedText:isRoot:) -> CoalescingDecision`：Task 1 测试/实现/EditingController 三处签名一致 ✓
- `EditingController.init(model:commandBus:)` + `begin/commit/cancel`：Task 1 一致 ✓
- `DocumentPersistence.adopt(document:fileURL:isDirty:keepLastSaved:regenerateID:clearRecovery:)`：Task 2 测试/实现/Session 委托三处一致 ✓
- `LayoutPipeline.init(layoutEngineType:measure:)` + `relayout(document:)`：Task 3 一致 ✓
- `DocumentSession.init` 参数演进：Task 2 加 `autosaveStore`/`securityScopedAccess` 保留兼容；Task 3 加 `layoutPipeline`；`DocumentSession(autosaveStore:)` 测试调用在 Task 2 (6) init 保留 ✓

**潜在风险与兜底：**
- `RadialLayout.layout` 完整签名需在 Task 3 Step 5 核对（确认返回 `LayoutSnapshot`），否则补显式转发。
- `DocumentSession` 现有测试中是否有 `DocumentSession(securityScopedAccess:)`/`DocumentSession(measure:)` 精确调用——Task 2/3 的 init 已保留这些参数默认值，兼容；若执行中发现某个参数被移除导致编译失败，保留该参数并在 init 内转发。
- `LayoutSnapshot` 未假设 Equatable：`LayoutPipelineTests` 用 `frames.count`/`isEmpty` 断言，避开协议一致性假设。
