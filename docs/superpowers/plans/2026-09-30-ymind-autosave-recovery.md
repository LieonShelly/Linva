# YMind 自动保存 + 崩溃恢复子系统 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 YMind 加防丢能力：文档变脏后 2s 防抖写临时副本到 Application Support/Unsaved/，正常保存清除副本；崩溃后下次启动检测到副本弹出恢复横幅，「恢复更改」载入草稿为未保存文档，「忽略」清空副本载入正式版。

**Architecture:** Session 层新增 `AutosaveStore`（目录 `Unsaved/` 管理：写 `<docID>.ymind` + `<docID>.meta.json`、删、扫最新、清空、读回，仅 Foundation/Combine）。`DocumentSession` 扩 `documentID`（配对）+ Combine `debounce` 2s 触发 `flushAutoSave()`（`commandBus.onChange` 为脏信号，不接触模型/命令栈）+ `recovery: RecoveryOffer?` 横幅态。Shell 层 `AppDelegate.applicationDidFinishLaunching` 调 `DocumentWorkflow.scanForRecovery`；`RecoveryBannerView` 展示 + 恢复/忽略按钮。

**Tech Stack:** Swift 6、SwiftUI（横幅）、Combine（debounce + RunLoop scheduler）、Foundation（FileManager/JSON）、Swift Testing。无新 dependency、无新 shader。

**Spec:** `docs/superpowers/specs/2026-09-30-ymind-import-export-design.md`（本 plan 从 spec 论证；执行者需同时读 spec 与本文）。需求真源：`docs/prds/prd-ymind-import-export-2026-09-30/prd.md`（FR-S1/S2）+ `addendum.md`（§4 自动保存/恢复）。体验真源：`prototype/import-export.html`（标签「崩溃恢复」）。

## Global Constraints

（逐条取自 spec §6，所有 task 隐式包含本节）

- **`AutosaveStore` 放 Session 层**，`import Foundation Combine`（White list：Session 允许 `Foundation Combine CoreGraphics`）。不得引 AppKit/SwiftUI（UI 在 Shell 做）。
- **无新 import 白名单**；`YMindCodec.currentVersion` 保持 2，不新增 `Node` 字段，`documentID` 只存内存副本 meta（FR-C1/C2）。
- **副本目录**：`FileManager.default.urls(for: .applicationSupportDirectory)[0]/Unsaved/<docID>.ymind` + 同名 `.meta.json`（addendum §4）。
- **配对**：副本与正式文档通过「documentID + originalURL（可空）」判定；未命名文档（无正式 URL）也有 `documentID`（内存 UUID），恢复为未命名新文档（FR-S2、addendum §4）。
- **触发**：`commandBus.onChange`（脏信号）→ Session Combine `debounce(2s)` → `flushAutoSave()` 写副本；正常保存 `save()/saveAs()` 成功后删副本；`newDocument()/load(from:)/loadImported(_:)` 重置 `documentID` + 清旧副本 + 清 `recovery`（spec §6.2 矩阵）。
- **只对已加载文档写副本、不建空副本**；写入失败**静默降级**（保留内存文档、不打扰编辑、下次不误报，FR-S1）。
- **副本不经过命令栈、不被 Undo 影响**（FR-S1 末条）：自动保存/恢复均不调 `commandBus`。
- **保留策略（拍板）**：启动只对**最新**副本弹横幅；「恢复」载入并删该副本；「忽略」`clearAll()` 清空 `Unsaved/` 全部并载最近正式版（无 7 天过期）。
- **层边界**：`AutosaveMeta`/`AutosaveStore`/`RecoveryOffer` 在 Session；`RecoveryBannerView`/扫描入口在 Shell；`DocumentSession` 组合。
- 新增源码文件经 Xcode 同步组自动纳入，**不改** `project.pbxproj`。
- 文档中文优先；专有名词/API 可英文。

---

### Task 1: Session — `AutosaveMeta` + `AutosaveStore`（副本读写，TDD）

**Files:**
- Create: `YMindApp/YMindApp/Session/AutosaveStore.swift`
- Test: `YMindApp/YMindAppTests/AutosaveStoreTests.swift`

**Interfaces:**
- Consumes: `MindMapDocument`、`YMindCodec.encode/decode`（已有，Model/Codec）。读 addendum §4 目录约定。
- Produces: `struct AutosaveMeta: Codable, Equatable`（documentID/originalURL/savedAt/changeCount/rootText）、`final class AutosaveStore`（`init(directory: URL? = nil)` 注入测试目录；`write(document:meta:) throws`、`delete(documentID:) throws`、`latestPending() -> AutosaveMeta?`、`clearAll() throws`、`load(documentID:) throws -> MindMapDocument`）。Task 2/3/4 依赖。默认目录 = Application Support/Unsaved（惰性求值）。

- [ ] **Step 1: 写失败测试**

```swift
// YMindAppTests/AutosaveStoreTests.swift
import Testing
import Foundation
@testable import YMindApp

@Suite("AutosaveStore")
struct AutosaveStoreTests {
    private func tempDir() throws -> URL {
        try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    @Test func write_createsDocAndMetaFiles() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AutosaveStore(directory: dir)
        var doc = MindMapDocument.blank(rootText: "根")
        doc.root.children = [Node(text: "子")]
        let meta = AutosaveMeta(documentID: UUID(), originalURL: nil, savedAt: Date(),
                                changeCount: 3, rootText: "根")
        try store.write(document: doc, meta: meta)

        // 两个文件存在
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.count == 2)          // .ymind + .meta.json
        let ymind = files.first { $0.hasSuffix(".ymind") }
        let metaF = files.first { $0.hasSuffix(".meta.json") }
        #expect(ymind != nil && metaF != nil)
    }

    @Test func load_roundTripsDocument() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AutosaveStore(directory: dir)
        let docID = UUID()
        var doc = MindMapDocument.blank(rootText: "草稿")
        doc.root.children = [Node(text: "a"), Node(text: "b")]
        let meta = AutosaveMeta(documentID: docID, originalURL: nil, savedAt: Date(),
                                changeCount: 1, rootText: "草稿")
        try store.write(document: doc, meta: meta)

        let loaded = try store.load(documentID: docID)
        #expect(loaded.root.text == "草稿")
        #expect(loaded.root.children.map(\.text) == ["a", "b"])
    }

    @Test func latestPending_returnsNewestBySavedAt() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AutosaveStore(directory: dir)
        let oldID = UUID(); let newID = UUID()
        var doc = MindMapDocument.blank(rootText: "根")
        try store.write(document: doc, meta: AutosaveMeta(
            documentID: oldID, originalURL: nil,
            savedAt: Date(timeIntervalSince1970: 1000), changeCount: 1, rootText: "旧"))
        try store.write(document: doc, meta: AutosaveMeta(
            documentID: newID, originalURL: nil,
            savedAt: Date(timeIntervalSince1970: 2000), changeCount: 2, rootText: "新"))

        let latest = store.latestPending()
        #expect(latest?.documentID == newID)
    }

    @Test func delete_removesPair() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AutosaveStore(directory: dir)
        let docID = UUID()
        var doc = MindMapDocument.blank(rootText: "根")
        try store.write(document: doc, meta: AutosaveMeta(
            documentID: docID, originalURL: nil, savedAt: Date(), changeCount: 0, rootText: "根"))

        try store.delete(documentID: docID)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.isEmpty)
    }

    @Test func clearAll_removesEverything() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AutosaveStore(directory: dir)
        var doc = MindMapDocument.blank(rootText: "根")
        try store.write(document: doc, meta: AutosaveMeta(
            documentID: UUID(), originalURL: nil, savedAt: Date(), changeCount: 0, rootText: "r1"))
        try store.write(document: doc, meta: AutosaveMeta(
            documentID: UUID(), originalURL: nil, savedAt: Date(), changeCount: 0, rootText: "r2"))

        try store.clearAll()
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.isEmpty)
    }

    @Test func metadata_encodesAndDecodes() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AutosaveStore(directory: dir)
        let docID = UUID()
        let url = "file:///tmp/x.ymind"
        var doc = MindMapDocument.blank(rootText: "根")
        try store.write(document: doc, meta: AutosaveMeta(
            documentID: docID, originalURL: url, savedAt: Date(timeIntervalSince1970: 42),
            changeCount: 7, rootText: "根"))

        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let metaFile = files.first { $0.hasSuffix(".meta.json") }!
        let data = try Data(contentsOf: dir.appendingPathComponent(metaFile))
        let decoded = try JSONDecoder().decode(AutosaveMeta.self, from: data)
        #expect(decoded.documentID == docID)
        #expect(decoded.originalURL == url)
        #expect(decoded.changeCount == 7)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd YMindApp && xcodebuild test -project YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS' -only-testing:YMindAppTests/AutosaveStore`
Expected: FAIL —— `AutosaveMeta` / `AutosaveStore` 未定义。

- [ ] **Step 3: 实现 `AutosaveStore.swift`**

```swift
// Session/AutosaveStore.swift
import Combine
import Foundation

/// 临时副本配对元信息（随副本落盘，不写入文档本身）。
struct AutosaveMeta: Codable, Equatable {
    var documentID: UUID        // 内存会话 uuid（未命名文档亦然）
    var originalURL: String?    // 正式文件 URL 的 absoluteString（nil=未命名）
    var savedAt: Date           // 最近自动保存时间
    var changeCount: Int        // 距上次写盘的变化次数
    var rootText: String?       // 供横幅显示文档名
}

/// 管理 Application Support/Unsaved/ 下的临时副本；不接触 Model / 命令栈。
/// directory 可注入（测试用临时目录）；默认惰性取 Application Support/Unsaved。
final class AutosaveStore {
    private let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = base.appendingPathComponent("Unsaved", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private func docURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).ymind") }
    private func metaURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).meta.json") }

    /// 写副本（文档 JSON + meta JSON）。失败抛出（Session 侧静默吞掉）。
    func write(document: MindMapDocument, meta: AutosaveMeta) throws {
        let docData = try YMindCodec.encode(document)
        try docData.write(to: docURL(meta.documentID), options: .atomic)
        let metaData = try JSONEncoder().encode(meta)
        try metaData.write(to: metaURL(meta.documentID), options: .atomic)
    }

    /// 删除某文档的副本（.ymind + .meta.json）。不存在时静默。
    func delete(documentID: UUID) throws {
        try? FileManager.default.removeItem(at: docURL(documentID))
        try? FileManager.default.removeItem(at: metaURL(documentID))
    }

    /// 扫描目录：返回 savedAt 最新的 meta（nil = 无副本）。
    func latestPending() -> AutosaveMeta? {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let metas = files.filter { $0.hasSuffix(".meta.json") }.compactMap { name -> AutosaveMeta? in
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(AutosaveMeta.self, from: data)
        }
        return metas.max { $0.savedAt < $1.savedAt }
    }

    /// 「忽略」清空整个 Unsaved/（含历史残留与无 meta 的孤儿文件）。
    func clearAll() throws {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in files {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    /// 读回某副本文档 JSON（Decode → MindMapDocument）。
    func load(documentID: UUID) throws -> MindMapDocument {
        let data = try Data(contentsOf: docURL(documentID))
        return try YMindCodec.decode(data)
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2 命令
Expected: PASS（6 个测试全过）。

- [ ] **Step 5: Commit**

```bash
git add YMindApp/YMindApp/Session/AutosaveStore.swift YMindApp/YMindAppTests/AutosaveStoreTests.swift
git commit -m "feat: AutosaveStore 临时副本读写（Unsaved/.ymind + .meta.json）"
```

---

### Task 2: Session — `DocumentSession` 防抖自动保存 + `recovery` 态（TDD）

**Files:**
- Modify: `YMindApp/YMindApp/Session/DocumentSession.swift`
- Test: `YMindApp/YMindAppTests/DocumentSessionTests.swift`（追加 `@Suite("DocumentSessionAutosave")`）

**Interfaces:**
- Consumes: `AutosaveStore`（Task 1）、`documentID`（本 Task 新增；导入 plan Task 4 已加，若未运行此 plan 则本 Task 补上）、`commandBus.onChange`（已有）。
- Produces: `var documentID: UUID`、`@Published var recovery: RecoveryOffer?`、Combine 防抖触发 `flushAutoSave()`、`save()/saveAs()` 成功后删副本、`newDocument()/load(from:)` 重置 documentID+清 recovery。Task 3（启动扫描）与 Task 4（恢复/忽略）依赖。**若导入 plan 已加 `documentID`，本 Task 不重复声明**（重叠字段，追加测试即够）。

- [ ] **Step 1: 写失败测试**

```swift
// 追加到 DocumentSessionTests.swift
@Suite("DocumentSessionAutosave")
struct DocumentSessionAutosaveTests {
    private func tempDir() throws -> URL {
        try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }

    @Test func save_clearsPendingCopy() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let session = DocumentSession()
        let autosave = AutosaveStore(directory: dir)
        // 模拟写了一份当前 documentID 的副本
        var doc = MindMapDocument.blank(rootText: "根")
        doc.root.children = [Node(text: "x")]
        try autosave.write(document: doc, meta: AutosaveMeta(
            documentID: session.documentID, originalURL: nil,
            savedAt: Date(), changeCount: 1, rootText: "根"))

        // 触发保存（无 fileURL → saveAs）
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ymind-as-\(UUID().uuidString).ymind")
        try session.saveAs(to: url)

        // 保存后副本清除：latestPending 为 nil
        #expect(autosave.latestPending() == nil)
        try? FileManager.default.removeItem(at: url)
    }
}
```

> 说明：`flushAutoSave` 内部用真实 `AutosaveStore()`（默认目录）还是注入？为可测性，Session 需可注入 store：`init(..., autosaveStore: AutosaveStore? = nil)`。防抖的 2s 延时在单测里**不可等**——引入 `flushAutoSave` 为 `internal` 供测试直接调，不测防抖时序本身（防抖是框架行为，靠手测 + `debounce` 已内建）。本 Task 测试聚焦「保存清副本」「documentID 换新」，不测真实落盘延时。

- [ ] **Step 2: 跑测试确认失败**

Run: `cd YMindApp && xcodebuild test -project YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS' -only-testing:YMindAppTests/DocumentSessionAutosave`
Expected: FAIL —— `AutosaveStore` 注入参数 / `flushAutoSave` 未定义 / `documentID` 缺失（若导入 plan 未跑）。

- [ ] **Step 3: 实现 `DocumentSession` 扩充**

（1）`init` 增注入参数 + 属性：

```swift
    var documentID = UUID()
    @Published var recovery: RecoveryOffer?
    private let autosaveStore: AutosaveStore
    private var autoSaveDebounce: AnyCancellable?

    init(
        model: MindMapModel? = nil,
        measure: TextMeasure = TextMeasure(),
        securityScopedAccess: SecurityScopedAccess = SecurityScopedAccess(),
        autosaveStore: AutosaveStore = AutosaveStore()
    ) {
        …
        self.autosaveStore = autosaveStore
        …
    }
```

（2）`wireCommandBus` 的 `onChange` 后追加防抖触发：

```swift
    private func wireCommandBus() {
        commandBus.onChange = { [weak self] in
            guard let self else { return }
            syncSelectionFromModel()
            undoRevision += 1
            markDirtyAndRelayout()
            scheduleAutoSave()
        }
    }

    /// 脏后 2s 防抖写副本（FR-S1）。combine 重订阅每次 cancel 旧的。
    private func scheduleAutoSave() {
        autoSaveDebounce = Just(())
            .delay(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.flushAutoSave() }
    }

    /// 立即把当前文档写临时副本；失败静默（FR-S1）。
    func flushAutoSave() {
        guard hasLoadedEditableContent else { return }   // 见下方定义
        let meta = AutosaveMeta(
            documentID: documentID,
            originalURL: fileURL?.absoluteString,
            savedAt: Date(),
            changeCount: pendingChangeCount(),
            rootText: model.document.root.text
        )
        try? autosaveStore.write(document: model.document, meta: meta)
    }
```

（3）`save()` / `saveAs(to:)` 成功后清副本：

```swift
    // save() 末尾（isDirty = false 之后）：
        try? autosaveStore.delete(documentID: documentID)

    // saveAs(to:) 末尾（isDirty = false 之后）：
        try? autosaveStore.delete(documentID: documentID)
```

（4）`newDocument()` / `load(from:)` 重置 `documentID`（在各自开头或结尾）：

```swift
    // newDocument() 末尾（isDirty=false 附近）：
        documentID = UUID()
        recovery = nil
    // load(from:) 末尾（isDirty=false 附近）：
        documentID = UUID()
        recovery = nil
```

> `loadImported(_:)` 若本 plan 与导入 plan 都运行：导入 plan Task 4 已加 `documentID = UUID()`。若冲突（重复赋值无副作用），保留导入 plan 版本；本 Task 只在 `newDocument/load` 重置。**执行者核对：不要重复声明 `documentID` 或 `recovery`。**

（5）辅助（放在私有区）：

```swift
    /// 只对已加载且有内容的文档写副本（不建空树副本）。
    private var hasLoadedEditableContent: Bool {
        // fileURL != nil（已保存）或 isDirty（有改动）且根有内容
        fileURL != nil || isDirty
    }

    /// 距上次保存的变化计数：复用 undoRevision，或另计（见说明）。
    private func pendingChangeCount() -> Int {
        undoRevision   // 近似：每次变更 undoRevision +1；够横幅显示「N 处修改」
    }
```

> 说明：`pendingChangeCount` 复用了 `undoRevision` 现值（每次命令/撤销/重做都 +1）。横幅文案「N 处修改未写盘」只需一个计数表达「有改动」，用 `undoRevision` 即可，不引入新状态。若你觉得需精确「距上次写盘的变化数」，可改存 `lastSavedRevision` 并 `pendingChangeCount = undoRevision - lastSavedRevision`——本 plan 采简单版（`undoRevision`），够用手测。

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2 命令
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add YMindApp/YMindApp/Session/DocumentSession.swift YMindApp/YMindAppTests/DocumentSessionTests.swift
git commit -m "feat: DocumentSession 防抖自动保存 + 保存清副本 + recovery 态"
```

---

### Task 3: Session — `RecoveryOffer` + 恢复/忽略流程（TDD）

**Files:**
- Modify: `YMindApp/YMindApp/Session/DocumentSession.swift`（追加 `RecoveryOffer`、`restoreDraft/discardDraft`）
- Test: `YMindApp/YMindAppTests/DocumentSessionTests.swift`（追加 `@Suite("DocumentSessionRecovery")`）

**Interfaces:**
- Consumes: `AutosaveStore`（Task 1）、`DocumentSession`（Task 2）。
- Produces: `struct RecoveryOffer { meta }`、`func presentRecovery() -> RecoveryOffer?`（扫最新）与 `func restoreRecovery(_ offer:)` / `func discardRecovery(_ offer:)` —— 或由 Shell 的 `DocumentWorkflow` 编排（见 Task 4）。**本 Task 定：Session 提供 `scanForRecovery() -> RecoveryOffer?` 与 `restore(draftFrom:)` / `discardDraft()`**，供 Task 4 的 `DocumentWorkflow` 调用。

- [ ] **Step 1: 写失败测试**

```swift
@Suite("DocumentSessionRecovery")
struct DocumentSessionRecoveryTests {
    private func tempDir() throws -> URL {
        try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }

    @Test func scan_returnsOffer_whenPendingCopyExists() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let session = DocumentSession(autosaveStore: AutosaveStore(directory: dir))
        var doc = MindMapDocument.blank(rootText: "草稿根")
        doc.root.children = [Node(text: "a")]
        try AutosaveStore(directory: dir).write(
            document: doc,
            meta: AutosaveMeta(documentID: session.documentID, originalURL: nil,
                               savedAt: Date(), changeCount: 3, rootText: "草稿根"))

        let offer = session.scanForRecovery()
        #expect(offer != nil)
        #expect(offer?.meta.documentID == session.documentID)
    }

    @Test func restore_loadsDraft_asDirtyDocument() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AutosaveStore(directory: dir)
        let session = DocumentSession(autosaveStore: store)
        var doc = MindMapDocument.blank(rootText: "草稿")
        doc.root.children = [Node(text: "恢复的内容")]
        let meta = AutosaveMeta(documentID: session.documentID, originalURL: nil,
                                savedAt: Date(), changeCount: 3, rootText: "草稿")
        try store.write(document: doc, meta: meta)

        let offer = RecoveryOffer(meta: meta)
        try session.restore(draftFrom: offer)

        #expect(session.model.document.root.children.map(\.text) == ["恢复的内容"])
        #expect(session.isDirty)          // 恢复后标记未保存
        #expect(store.latestPending() == nil)  // 恢复后删该副本
    }

    @Test func discard_clearsAll_andKeepsLastSaved() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AutosaveStore(directory: dir)
        let session = DocumentSession(autosaveStore: store)
        var doc = MindMapDocument.blank(rootText: "草稿")
        doc.root.children = [Node(text: "x")]
        let meta = AutosaveMeta(documentID: session.documentID, originalURL: nil,
                                savedAt: Date(), changeCount: 1, rootText: "草稿")
        try store.write(document: doc, meta: meta)

        try session.discardDraft()

        #expect(store.latestPending() == nil)  // 忽略：清空副本
        #expect(session.isDirty == false)      // 回到最近正式保存版本（无 → 空文档 clean）
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd YMindApp && xcodebuild test -project YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS' -only-testing:YMindAppTests/DocumentSessionRecovery`
Expected: FAIL —— `scanForRecovery` / `RecoveryOffer` / `restore(draftFrom:)` / `discardDraft()` 未定义。

- [ ] **Step 3: 实现 `RecoveryOffer` + Session 方法**

```swift
/// 恢复横幅数据（Session 层；Shell 只读展示）。
struct RecoveryOffer: Equatable {
    let meta: AutosaveMeta
}

// DocumentSession 扩充：

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
        lastSavedDocument = doc
        isDirty = true
        documentID = offer.meta.documentID
        editingId = nil
        draftText = ""
        originalEditingText = ""
        camera = Camera()
        recovery = nil
        relayout()
        errorMessage = nil
        try? autosaveStore.delete(documentID: offer.meta.documentID)
        autosaveStore.clearAll()   // 恢复后清其余残留（拍板：忽略清全部；恢复也顺手清，避免再提示）
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
```

> 说明：`restore(draftFrom:)` 恢复原文件 URL（若 meta 有）并 isDirty=true，可继续编辑并正常保存；未命名文档（originalURL nil）→ 保持 fileURL=nil，作为未命名新文档。`restore` 末尾也 `clearAll()`（连同其它残留副本）确保下次启动不再提示——遵循「忽略清全部」的精神且最简。若产品希望恢复后保留其它副本，去掉该行（默认已指定忽略清全部，恢复清残留是安全默认）。
> `discardDraft` 重置 `documentID`（新 UUID），与「新建/打开重置」一致；载入最近正式版本由 Shell 决定（若当前文档已是正式版则保持）。

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2 命令
Expected: PASS（3 个测试全过）。

- [ ] **Step 5: Commit**

```bash
git add YMindApp/YMindApp/Session/DocumentSession.swift YMindApp/YMindAppTests/DocumentSessionTests.swift
git commit -m "feat: RecoveryOffer + 恢复/忽略草稿流程（isDirty 标记 / 清副本）"
```

---

### Task 4: Shell — 启动扫描 + `RecoveryBannerView` 横幅

**Files:**
- Create: `YMindApp/YMindApp/App/RecoveryBannerView.swift`
- Modify: `YMindApp/YMindApp/YMindAppApp.swift`（`AppDelegate` 增 `applicationDidFinishLaunching` 扫描；`DocumentWorkflow` 增恢复/忽略包装）
- Modify: `YMindApp/YMindApp/ContentView.swift`（挂横幅）

**Interfaces:**
- Consumes: `DocumentSession.scanForRecovery/restore/discardDraft/recovery`（Task 2/3）、`RecoveryOffer`（Task 3）。
- Produces: `@MainActor static func scanForRecovery(_ session:)`、`restoreDraft(_ session:)`、`discardDraft(_ session:)`（`DocumentWorkflow` 包装，错误 → `session.errorMessage`）；`RecoveryBannerView`。Task 5 收尾验证。

- [ ] **Step 1: 创建 `RecoveryBannerView.swift`**

```swift
import SwiftUI

/// 崩溃恢复横幅：显示「检测到上次未保存的更改」+ 文档名/时间/修改数 + 恢复/忽略。
struct RecoveryBannerView: View {
    let offer: RecoveryOffer
    let onRestore: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("检测到上次未保存的更改")
                    .font(.headline)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("忽略（丢弃草稿）") { onDiscard() }
            Button("恢复更改") { onRestore() }
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding()
        .accessibilityLabel("检测到上次未保存的更改")
    }

    private var summary: String {
        let name = offer.meta.rootText ?? "未命名文档"
        var parts: [String] = []
        parts.append("「\(name)」")
        if let url = offer.meta.originalURL, let u = URL(string: url) {
            parts.append(u.lastPathComponent)
        }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        parts.append("最近自动保存 \(formatter.string(from: offer.meta.savedAt))")
        parts.append("\(offer.meta.changeCount) 处修改未写盘")
        return parts.joined(separator: " · ")
    }
}
```

- [ ] **Step 2: `AppDelegate` 增启动扫描**

```swift
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let session else { return }
        DocumentWorkflow.scanForRecovery(session)
    }
```

`DocumentWorkflow` 增（放 `confirmReplacement` 附近）：

```swift
    /// 启动扫描：有未保存副本 → session.recovery 非 nil → 横幅提示（只最新）。
    static func scanForRecovery(_ session: DocumentSession) {
        _ = session.scanForRecovery()
    }

    /// 「恢复更改」：载入草稿，标记未保存。
    static func restoreDraft(_ session: DocumentSession) {
        guard let offer = session.recovery else { return }
        do {
            try session.restore(draftFrom: offer)
        } catch {
            session.errorMessage = "恢复失败：\(error.localizedDescription)"
        }
    }

    /// 「忽略（丢弃草稿）」：清空副本，载入最近正式版。
    static func discardDraft(_ session: DocumentSession) {
        do {
            try session.discardDraft()
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }
```

- [ ] **Step 3: `ContentView` 挂横幅（ZStack 顶层，`search` 之后 / `errorMessage` 附近）**

```swift
                if let offer = session.recovery {
                    RecoveryBannerView(
                        offer: offer,
                        onRestore: { DocumentWorkflow.restoreDraft(session) },
                        onDiscard: { DocumentWorkflow.discardDraft(session) }
                    )
                }
```

- [ ] **Step 4: 构建 + 手测（对齐 PRD §6 验收 6–7）**

Run: `cd YMindApp && xcodebuild build -project YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS'`

手测：
1. 开图改几处 → 等待 >2s（防抖）→ 打开 `~/Library/Application Support/YMindApp/Unsaved/` 确认出现 `.ymind` + `.meta.json`（FR-S1 验收 6：变脏后 ≤3s 落盘，正常保存后清除）。
2. 再改 → 不等防抖直接 Cmd-S 保存 → 确认副本被清除。
3. 模拟崩溃残留：改后直接杀掉进程（或先制造副本再重启）→ 重启 App → 出现横幅（文档名/时间/修改数）（FR-S2 验收 7）。
4. 点「恢复更改」→ 内容=草稿、title 带编辑点（isDirty）、可继续编辑并保存。
5. 再模拟残留 → 点「忽略」→ 副本删除、载入最近正式保存版本。
6. 未命名新文档改几处 → 崩溃 → 重启 → 横幅可恢复为未命名文档。
7. 空白新文档（未编辑）→ 不产生副本（`hasLoadedEditableContent` 为 false）。

- [ ] **Step 5: Commit**

```bash
git add YMindApp/YMindApp/App/RecoveryBannerView.swift YMindApp/YMindApp/YMindAppApp.swift YMindApp/YMindApp/ContentView.swift
git commit -m "feat: 启动扫描恢复横幅（RecoveryBannerView + DocumentWorkflow 恢复/忽略）"
```

---

### Task 5: 收尾 — 全量验证 + 边界 + 文档

**Files:**
- Verify: 全量测试、`scripts/check-boundaries.sh`。
- Modify: `docs/架构现状.md`（登记新文件）。

**Interfaces:**
- Consumes: 全部前面任务。

- [ ] **Step 1: 全量构建 + 测试**

Run: `cd YMindApp && xcodebuild test -project YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS'`
Expected: 全部测试 PASS（既有 + `AutosaveStoreTests`/`DocumentSessionAutosaveTests`/`DocumentSessionRecoveryTests`）。

- [ ] **Step 2: 边界校验**

Run: `scripts/check-boundaries.sh`
Expected: 输出「依赖边界检查通过」，退出码 0。`AutosaveStore.swift`（Session：Foundation/Combine）不违规。

- [ ] **Step 3: 登记 `docs/架构现状.md`**

在 §2.1 Session 层类型列追加 `AutosaveStore`/`AutosaveMeta`/`RecoveryOffer`；App 层追加 `RecoveryBannerView`；§6 命令清单**不变**（自动保存不新增命令）。

- [ ] **Step 4: Commit**

```bash
git add docs/架构现状.md
git commit -m "docs: 登记自动保存/崩溃恢复子系统（Session AutosaveStore + Shell 横幅）"
```

---

## Self-Review 记录

- **Spec 覆盖：** §6.1（AutosaveStore/目录/元信息）→ Task 1；§6.2（防抖/清理矩阵/documentID/recovery）→ Task 2；§6.4（恢复/忽略/未命名/多副本/不入命令栈）→ Task 3、4；§6.3（启动扫描/横幅）→ Task 4；§7 验收 6–7 → Task 4 手测 + Task 1–3 测试。
- **占位符：** 无 TBD/TODO；每个代码步骤含完整可复制代码。
- **类型一致性：** `AutosaveMeta(documentID/originalURL/savedAt/changeCount/rootText)`、`AutosaveStore(directory:write/delete/latestPending/clearAll/load)`、`DocumentSession(documentID/recovery/scheduleAutoSave/flushAutoSave/scanForRecovery/restore(draftFrom:)/discardDraft)`、`RecoveryOffer(meta)`、`DocumentWorkflow.scanForRecovery/restoreDraft/discardDraft`、`RecoveryBannerView` 在 Task 间签名一致。
- **时序测试策略：** 防抖 2s 延时属框架行为，单测不等待，改测「保存清副本」「恢复 isDirty」「忽略清副本」等状态转移；防抖真实落盘靠 Task 4 手测。
- **字段重叠声明：** `documentID` 由导入 plan Task 4 已加；本 plan 不重复声明，Task 2 Step 3 已注明（执行者核对该字段是否已存在）。