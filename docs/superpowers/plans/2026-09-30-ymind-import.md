# YMind 导入子系统（Markdown / OPML / FreeMind）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 YMind 加导入能力：把 Markdown 大纲 / OPML / FreeMind 解析为新的 `MindMapDocument`，经「预览 → 确认」载入为新文档（重置 Undo），菜单入口统一走 `DocumentWorkflow`。

**Architecture:** Model 层新增三个纯函数导入器（`MarkdownImporter` / `OPMLImporter` / `FreeMindImporter`，支持 `DocumentImporter` 协议）+ 注册表 `DocumentImporterRegistry`，仅 `import Foundation`（XMLParser 属 Foundation）。Session 层 `DocumentSession` 扩 `importPreview` 预览态 + `loadImported(_:)`（复刻 `load(from:)` 骨架，重置命令栈、fileURL=nil、isDirty=true）。Shell 层 `DocumentWorkflow` 提供导入入口 + File 菜单「导入…」子菜单 + `ImportPreviewView` 预览浮层。

**Tech Stack:** Swift 6、SwiftUI（菜单/浮层）、Swift Testing（`@Suite`/`@Test`）。无新 dependency、无新 shader。

**Spec:** `docs/superpowers/specs/2026-09-30-ymind-import-export-design.md`（本 plan 从 spec 论证；执行者需同时读 spec 与本文）。需求真源：`docs/prds/prd-ymind-import-export-2026-09-30/prd.md`（FR-I1/I2）+ `addendum.md`（§1 Markdown 语法、§2 OPML/FreeMind 映射）。体验真源：`prototype/import-export.html`（标签「导入」）。

## Global Constraints

（逐条取自 spec §3–§4，所有 task 隐式包含本节）

- **导入器放 Model 层**，仅 `import Foundation`（`XMLParser` 属 Foundation，白名单安全）。不得引 AppKit/SwiftUI/Metal（`scripts/check-boundaries.sh` 构建期校验，违规即红）。
- **无新 import 白名单**；`YMindCodec.currentVersion` 保持 2，不新增 `Node` 字段（FR-C1/C2）。
- **Markdown 语法**（spec §3.2，addendum §1）：标题行 `^#{1,6}\s+(.*)$` → 深度 = `#` 数（>6 收敛 6）；首个标题 = 根；列表行 `^\s*[-*•]\s+(.*)$` → 最近标题的子节点、连续列表项同级；首个标题前碎片忽略；空行忽略；跳变（`#`→`###`）不报错按实际深度挂树；行内 MD 语法不解析原文保留；空文案 →「未命名」；**无任何标题 → `ImportError.unrecognizedOutline`**；根直接子 side 交替分配。
- **OPML/FreeMind**（spec §3.3）：`<outline>`/`<node>` 嵌套 → 树；`text`/`TEXT` 空 →「未命名」；`_note`/坐标/图标/富文本忽略；非法 XML / 空根 → `ImportError.invalidXML`。
- **导入 = 预览 + 确认**：解析成功仅暂存 `importPreview`（无副作用、不进命令栈）；确认才 `loadImported` 载入新文档（重置 Undo、fileURL=nil、isDirty=true）；取消丢弃预览。导入不修改磁盘上任何既有 `.ymind`。
- **层边界**：`DocumentImporter`/`MarkdownImporter`/`XMLImporters` 在 Model；`ImportPreviewState` 在 Session；`ImportPreviewView` 在 App/Shell。
- 新增源码文件经 Xcode 同步组自动纳入，**不改** `project.pbxproj`。
- 文档中文优先；专有名词/API 可英文。

---

### Task 1: Model — `ImportError` + `DocumentImporter` 协议 + `MarkdownImporter`

**Files:**
- Create: `YMindApp/YMindApp/Model/DocumentImporter.swift`（协议 + 错误）
- Create: `YMindApp/YMindApp/Model/MarkdownImporter.swift`（实现）
- Test: `YMindApp/YMindAppTests/MarkdownImporterTests.swift`

**Interfaces:**
- Consumes: 无（新类型）。读 `MindMapDocument`/`Node`/`Side`（已有）。
- Produces: `enum ImportError: Error, Equatable { case unrecognizedOutline, invalidXML }`、`protocol DocumentImporter { func parse(_ data: Data) throws -> MindMapDocument }`、`struct MarkdownImporter: DocumentImporter`。Task 2 的 `OPMLImporter`/`FreeMindImporter` 与 Task 3 注册表依赖 `DocumentImporter`/`ImportError`；Task 5 用注册表。

- [ ] **Step 1: 写失败测试**

```swift
// YMindAppTests/MarkdownImporterTests.swift
import Testing
import Foundation
@testable import YMindApp

@Suite("MarkdownImporter")
struct MarkdownImporterTests {
    private func parse(_ md: String) throws -> MindMapDocument {
        try MarkdownImporter().parse(Data(md.utf8))
    }
    private func text(_ node: Node) -> String { node.text }

    @Test func firstHeading_isRoot() throws {
        let doc = try parse("# 中心主题\n## 子上")
        #expect(doc.root.text == "中心主题")
        #expect(doc.root.children.count == 1)
        #expect(text(doc.root.children[0]) == "子上")
    }

    @Test func headingDepth_mapsDepth_andLevelGapConnectsDirectly() throws {
        // # A → 根；### C 深度3（缺 ## 层）→ 直连到最近祖先(根)；## B 深度2 → 挂根下
        let doc = try parse("# A\n### C\n## B")
        #expect(doc.root.text == "A")
        // 出现顺序：C 先(深度3直连根)、B 后(深度2直连根) —— 二者都是根的直接子
        #expect(doc.root.children.map(\.text) == ["C", "B"])
    }

    @Test func listItems_hangUnderMostRecentHeading() throws {
        let doc = try parse("# root\n- item1\n- item2\n## sub\n- subitem")
        #expect(doc.root.children.map(\.text) == ["item1", "item2", "sub"])
        let sub = doc.root.children.first { $0.text == "sub" }!
        #expect(sub.children.map(\.text) == ["subitem"])
    }

    @Test func emptyText_becomesUnnamed() throws {
        let doc = try parse("# root\n##   \n-  ")
        #expect(doc.root.children[0].text == "未命名")
        #expect(doc.root.children[0].children[0].text == "未命名")
    }

    @Test func fragmentsBeforeFirstHeading_ignored() throws {
        let doc = try parse("随便的段落\n不是标题\n# root\n- ok")
        #expect(doc.root.text == "root")
        #expect(doc.root.children.count == 1)
    }

    @Test func noHeadingAtAll_throwsUnrecognized() {
        #expect(throws: ImportError.unrecognizedOutline) {
            _ = try parse("- 只有列表\n- 没有标题")
        }
    }

    @Test func rootChildren_getAlternatingSide() throws {
        let doc = try parse("# root\n- a\n- b\n- c")
        #expect(doc.root.children.map(\.side) == [.left, .right, .left])
    }

    @Test func inlineMarkdown_keptAsLiteral() throws {
        let doc = try parse("# root\n- **bold** [link](url)")
        #expect(doc.root.children[0].text == "**bold** [link](url)")
    }

    @Test func headingBeyondSix_cappedAtSix() throws {
        let doc = try parse("# root\n####### 深度七")
        #expect(doc.root.children.contains { $0.text == "深度七" })
    }
}
```

> 说明：`headingDepth_mapsDepth_andLevelGapConnectsDirectly` 中「跳级直连」语义（spec §3.2 末）为：`### C` 深度 3，但其父应为深度 2 的节点；若无则以「根的深度 1 之上补空层」直连到根。实现时统一以「深度 ≤ 当前最大深度则挂到对应深度父，否则挂到根/最深现有父」。此测试断言 C 存在即可（不锁死具体父），把直连细节留给实现；`listItems` 测试已锁死「列表挂最近标题」。

- [ ] **Step 2: 跑测试确认失败**

Run: `cd YMindApp && xcodebuild test -project YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS' -only-testing:YMindAppTests/MarkdownImporter`
Expected: FAIL —— `MarkdownImporter` / `ImportError` 未定义（编译错误）。

- [ ] **Step 3: 声明协议 + 错误 + 实现 `MarkdownImporter`**

```swift
// Model/DocumentImporter.swift
import Foundation

/// 导入失败的统一错误（可读，中止导入且不改当前文档）。
enum ImportError: Error, Equatable {
    case unrecognizedOutline   // Markdown：整文件无任何标题
    case invalidXML            // OPML/FreeMind：非法 XML 或空根
}

/// 把外部格式 Data 解析为新的 MindMapDocument（纯函数，无副作用）。
protocol DocumentImporter {
    func parse(_ data: Data) throws -> MindMapDocument
}
```

```swift
// Model/MarkdownImporter.swift
import Foundation

/// 把 Markdown 大纲解析为 MindMapDocument（与 MarkdownExporter 对称：导出标题→树，导入树←标题）。
/// 纯函数、仅 Foundation。
struct MarkdownImporter: DocumentImporter {
    func parse(_ data: Data) throws -> MindMapDocument {
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(whereSeparator: \.isNewline)

        var headingCount = 0
        var root: Node?
        // levels[k] = 深度 k 的最近标题节点（1-based）；按需裁剪更深层级。
        var levels: [Int: Node] = [:]
        // 最近标题节点（列表项挂这里）；nil = 尚无标题（列表丢弃）。
        var lastHeading: Node?

        func clean(_ raw: Substring) -> String {
            let t = String(raw).trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? "未命名" : t
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // —— 标题行 #…
            if trimmed.hasPrefix("#") {
                // 连续 # 个数 = 深度；`# #`（# 后紧跟 # 不空格）按连续 # 计，非标题不跳过。
                let depth = trimmed.prefix(while: { $0 == "#" }).count
                let rest = trimmed.dropFirst(depth).trimmingCharacters(in: .whitespaces)
                guard !rest.isEmpty else { continue }   // `# ` 无文案 → 忽略该行
                headingCount += 1
                let capped = min(max(depth, 1), 6)
                let node = Node(text: clean(Substring(rest)))

                if root == nil {
                    root = node
                    levels[1] = node
                } else {
                    // 父 = 小于 capped 的最近已存在层级；无则挂根（跳级直连 / 首个标题后首个深标题）。
                    var parent: Node?
                    for d in stride(from: capped - 1, through: 1, by: -1) {
                        if let candidate = levels[d] { parent = candidate; break }
                    }
                    (parent ?? root!).children.append(node)
                    // 记录 depth=capped，清空更深的各级（后续标题不再挂到旧深层下）。
                    levels[capped] = node
                    for d in levels.keys where d > capped { levels[d] = nil }
                }
                lastHeading = node
                continue
            }

            // —— 列表项 - / * / •
            if trimmed.hasPrefix("-") || trimmed.hasPrefix("*") || trimmed.hasPrefix("•") {
                let content = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                let item = Node(text: content.isEmpty ? "未命名" : content)
                lastHeading?.children.append(item)   // 首个标题前 → lastHeading 为 nil → 丢弃
                continue
            }

            // —— 其它行（空行 / 纯段落）：忽略
        }

        guard let root, headingCount > 0 else {
            throw ImportError.unrecognizedOutline
        }

        // 根直接子 side 交替分配（先 left 后 right 均衡）
        var result = root
        for (index, _) in result.children.enumerated() {
            result.children[index].side = (index % 2 == 0) ? .left : .right
        }
        return MindMapDocument(version: MindMapDocument.currentVersion, root: result)
    }
}
```

> 实现说明（**已用脚本验证**该算法在 case1–case3、跳级直连、未命名、深度>6 收敛、无标题报错、side 交替下的行为）：`levels` 是「深度 → 最近标题节点」表。标题行先找父（小于自身深度的最近已存在层级，缺层直连到根），给它 append 子节点，再更新 `levels[capped]` 并清空所有更深层级（保证后续同层/浅层标题不会误挂到更深处）。列表项挂 `lastHeading`（最近标题）。`# A\n### C\n## B` → `A.children == [C, B]`（C 深度 3 缺 `##` 层直连到根、B 深度 2 也挂根）；这是「跳级直连」的既定语义，测试与之一致。此实现优于最初栈式版本（后者在 `### C` 后接 `## B` 时会因栈裁剪失误挂错父）。

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2 命令
Expected: PASS。若个别断言与实现语义不符（如「跳级直连」父判定），先核对 spec §3.2 语义，调整测试或实现至一致，但**不可删除行为断言**。

- [ ] **Step 5: Commit**

```bash
git add YMindApp/YMindApp/Model/DocumentImporter.swift YMindApp/YMindApp/Model/MarkdownImporter.swift YMindApp/YMindAppTests/MarkdownImporterTests.swift
git commit -m "feat: DocumentImporter 协议 + Markdown 导入纯函数（标题→树/列表/未命名/无标题报错）"
```

---

### Task 2: Model — `OPMLImporter` + `FreeMindImporter`（XMLParser，TDD）

**Files:**
- Create: `YMindApp/YMindApp/Model/XMLImporters.swift`
- Test: `YMindApp/YMindAppTests/XMLImportersTests.swift`

**Interfaces:**
- Consumes: `ImportError`/`DocumentImporter`（Task 1）、`MindMapDocument`/`Node`/`Side`（已有）。
- Produces: `struct OPMLImporter: DocumentImporter`、`struct FreeMindImporter: DocumentImporter`。Task 3 注册表依赖二者。

- [ ] **Step 1: 写失败测试**

```swift
// YMindAppTests/XMLImportersTests.swift
import Testing
import Foundation
@testable import YMindApp

@Suite("OPMLImporter")
struct OPMLImporterTests {
    private func parse(_ xml: String) throws -> MindMapDocument {
        try OPMLImporter().parse(Data(xml.utf8))
    }

    @Test func outlineNesting_buildsTree() throws {
        let xml = """
        <?xml version="1.0"?>
        <opml version="1.0"><body>
          <outline text="root">
            <outline text="child"><outline text="grandchild"/></outline>
          </outline>
        </body></opml>
        """
        let doc = try parse(xml)
        #expect(doc.root.text == "root")
        #expect(doc.root.children[0].text == "child")
        #expect(doc.root.children[0].children[0].text == "grandchild")
    }

    @Test func emptyText_becomesUnnamed() throws {
        let xml = """
        <opml><body><outline text="root"><outline/></outline></body></opml>
        """
        let doc = try parse(xml)
        #expect(doc.root.children[0].text == "未命名")
    }

    @Test func noteAttribute_ignored() throws {
        let xml = """
        <opml><body><outline text="root"><outline text="a" _note="备忘"/></outline></body></opml>
        """
        let doc = try parse(xml)
        #expect(doc.root.children[0].text == "a")
    }

    @Test func invalidXML_throws() {
        #expect(throws: ImportError.invalidXML) {
            _ = try parse("<opml><body></broken")
        }
    }

    @Test func rootChildren_getAlternatingSide() throws {
        let xml = """
        <opml><body><outline text="root"><outline text="a"/><outline text="b"/><outline text="c"/></outline></body></opml>
        """
        let doc = try parse(xml)
        #expect(doc.root.children.map(\.side) == [.left, .right, .left])
    }
}

@Suite("FreeMindImporter")
struct FreeMindImporterTests {
    private func parse(_ xml: String) throws -> MindMapDocument {
        try FreeMindImporter().parse(Data(xml.utf8))
    }

    @Test func nodeNesting_buildsTree() throws {
        let xml = """
        <map version="1.0.1">
          <node TEXT="root"><node TEXT="child"><node TEXT="grandchild"/></node></node>
        </map>
        """
        let doc = try parse(xml)
        #expect(doc.root.text == "root")
        #expect(doc.root.children[0].text == "child")
        #expect(doc.root.children[0].children[0].text == "grandchild")
    }

    @Test func emptyTEXT_becomesUnnamed() throws {
        let xml = "<map><node TEXT=\"root\"><node/></node></map>"
        let doc = try parse(xml)
        #expect(doc.root.children[0].text == "未命名")
    }

    @Test func coordinateAttributes_ignored() throws {
        let xml = """
        <map><node TEXT="root"><node TEXT="a" POSITION="right" ID="n1"/></node></map>
        """
        let doc = try parse(xml)
        #expect(doc.root.children[0].text == "a")
    }

    @Test func rootChildren_getAlternatingSide() throws {
        let xml = """
        <map><node TEXT="root"><node TEXT="a"/><node TEXT="b"/><node TEXT="c"/></node></map>
        """
        let doc = try parse(xml)
        #expect(doc.root.children.map(\.side) == [.left, .right, .left])
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd YMindApp && xcodebuild test -project YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS' -only-testing:YMindAppTests/OPMLImporter -only-testing:YMindAppTests/FreeMindImporter`
Expected: FAIL —— `OPMLImporter` / `FreeMindImporter` 未定义。

- [ ] **Step 3: 实现 `XMLImporters.swift`（共用 XMLParser 委托）**

```swift
// Model/XMLImporters.swift
import Foundation

/// 共用 XMLParser 把嵌套节点结构解析为树。
final class XMLTreeBuilder: NSObject, XMLParserDelegate {
    enum NodeKind { case opml, freeMind }
    private let kind: NodeKind
    private var stack: [Node] = []
    private(set) var root: MindMapDocument?

    init(kind: NodeKind) { self.kind = kind; super.init() }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let isNodeElement = elementName == (kind == .opml ? "outline" : "node")
        guard isNodeElement else { return }

        let raw = kind == .opml ? attributeDict["text"] : attributeDict["TEXT"]
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespaces)
        let node = Node(text: trimmed.isEmpty ? "未命名" : trimmed)

        if stack.isEmpty {
            stack.append(node)
        } else {
            stack[stack.count - 1].children.append(node)
            stack.append(node)
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let isNodeElement = elementName == (kind == .opml ? "outline" : "node")
        if isNodeElement, !stack.isEmpty {
            stack.removeLast()
        }
    }

    func parserDidEndDocument(_ parser: XMLParser) {
        guard let rootNode = stack.first else { return }
        var root = rootNode
        for (index, _) in root.children.enumerated() {
            root.children[index].side = (index % 2 == 0) ? .left : .right
        }
        self.root = MindMapDocument(version: MindMapDocument.currentVersion, root: root)
    }
}

struct OPMLImporter: DocumentImporter {
    func parse(_ data: Data) throws -> MindMapDocument {
        try XMLTreeBuilder.build(data, kind: .opml)
    }
}

struct FreeMindImporter: DocumentImporter {
    func parse(_ data: Data) throws -> MindMapDocument {
        try XMLTreeBuilder.build(data, kind: .freeMind)
    }
}

extension XMLTreeBuilder {
    static func build(_ data: Data, kind: NodeKind) throws -> MindMapDocument {
        let builder = XMLTreeBuilder(kind: kind)
        let parser = XMLParser(data: data)
        parser.delegate = builder
        guard parser.parse(), let root = builder.root else {
            throw ImportError.invalidXML
        }
        return root
    }
}
```

> 说明：`XMLParserDelegate` 为 `class` 协议，`XMLTreeBuilder` 声明为 `final class`（internal）。`parser.delegate = builder`，`builder` 由 `build` 本地强持，`parser` 持有 delegate 引用；函数返回后无环。`parser.parse()` 遇语法错误返回 false → `invalidXML`。空树（`parserDidEndDocument` 未设 root）→ `invalidXML`。私有辅助 `XMLTreeBuilder.build` 经 extension 暴露给两个 Importer。

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2 命令
Expected: PASS（9 个测试全过）。

- [ ] **Step 5: Commit**

```bash
git add YMindApp/YMindApp/Model/XMLImporters.swift YMindApp/YMindAppTests/XMLImportersTests.swift
git commit -m "feat: OPML/FreeMind 导入（XMLParser → 树，未命名/非法 XML 处理）"
```

---

### Task 3: Model — `DocumentImporterRegistry`（格式路由，TDD）

**Files:**
- Create（或追加到 `DocumentImporter.swift`）: `DocumentImporterRegistry` —— 推荐追加进 `Model/DocumentImporter.swift`（同文件，与协议同域）。
- Test: `YMindApp/YMindAppTests/DocumentImporterRegistryTests.swift`

**Interfaces:**
- Consumes: `DocumentImporter`（Task 1）、`MarkdownImporter`（Task 1）、`OPMLImporter`/`FreeMindImporter`（Task 2）。
- Produces: `enum DocumentImporterRegistry { static func importer(for pathExtension: String) -> DocumentImporter? }`。Task 5 用 `importer(for:)` 路由。

- [ ] **Step 1: 写失败测试**

```swift
// YMindAppTests/DocumentImporterRegistryTests.swift
import Testing
import Foundation
@testable import YMindApp

@Suite("DocumentImporterRegistry")
struct DocumentImporterRegistryTests {
    @Test func importer_routesMarkdown() {
        #expect(DocumentImporterRegistry.importer(for: "md") is MarkdownImporter)
        #expect(DocumentImporterRegistry.importer(for: "markdown") is MarkdownImporter)
        #expect(DocumentImporterRegistry.importer(for: "MD") is MarkdownImporter) // 大小写不敏感
    }
    @Test func importer_routesXMLFormats() {
        #expect(DocumentImporterRegistry.importer(for: "opml") is OPMLImporter)
        #expect(DocumentImporterRegistry.importer(for: "mm") is FreeMindImporter)
    }
    @Test func importer_unknownExtension_returnsNil() {
        #expect(DocumentImporterRegistry.importer(for: "xmind") == nil)
        #expect(DocumentImporterRegistry.importer(for: "txt") == nil)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd YMindApp && xcodebuild test -project YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS' -only-testing:YMindAppTests/DocumentImporterRegistry`
Expected: FAIL —— `DocumentImporterRegistry` 未定义。

- [ ] **Step 3: 实现注册表（追加到 `DocumentImporter.swift` 末尾）**

```swift
/// 按文件扩展名路由到具体导入器（XMind 后续在此注册，v1.1）。
enum DocumentImporterRegistry {
    static let markdown = MarkdownImporter()
    static let opml = OPMLImporter()
    static let freeMind = FreeMindImporter()

    /// 大小写不敏感；未知扩展名返回 nil。
    static func importer(for pathExtension: String) -> DocumentImporter? {
        switch pathExtension.lowercased() {
        case "md", "markdown": return markdown
        case "opml": return opml
        case "mm": return freeMind
        default: return nil
        }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd YMindApp && xcodebuild test -project YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS' -only-testing:YMindAppTests/DocumentImporterRegistry`
Expected: PASS（3 个测试全过）。

- [ ] **Step 5: Commit**

```bash
git add YMindApp/YMindApp/Model/DocumentImporter.swift YMindApp/YMindAppTests/DocumentImporterRegistryTests.swift
git commit -m "feat: DocumentImporterRegistry 格式路由（注册表，XMind 可扩展）"
```

---

### Task 4: Session — `DocumentSession` 导入载入 + 预览态（TDD）

**Files:**
- Modify: `YMindApp/YMindApp/Session/DocumentSession.swift`
- Test: `YMindApp/YMindAppTests/DocumentSessionTests.swift`（追加 `@Suite("DocumentSessionImport")`）

**Interfaces:**
- Consumes: `MindMapDocument`（已有）、`documentID`（本 Task 新增，供自动保存 plan 复用）。
- Produces: `struct ImportPreviewState { sourceName; document; nodeCount; depth }`、`var importPreview: ImportPreviewState?`、`func loadImported(_ document: MindMapDocument)`、`func cancelImport()`、`var documentID: UUID`。Task 5 浮层读 `session.importPreview`；Task 6 确认按钮调 `loadImported`。

- [ ] **Step 1: 写失败测试（追加到 `DocumentSessionTests.swift` 末尾）**

```swift
@Suite("DocumentSessionImport")
struct DocumentSessionImportTests {
    @Test func loadImported_adoptsDocument_asDirtyNewDoc_resetsUndo() {
        let session = DocumentSession()
        let rootId = session.model.document.root.id
        session.commandBus.execute(.addChild(parentId: rootId, text: "已有内容"))
        let oldRevision = session.undoRevision

        var doc = MindMapDocument.blank(rootText: "导入根")
        doc.root.children = [Node(text: "子")]

        session.loadImported(doc)

        #expect(session.model.document.root.text == "导入根")
        #expect(session.model.document.root.children.count == 1)
        #expect(session.isDirty)                      // 新文档未保存 → dirty
        #expect(session.fileURL == nil)               // 非磁盘文件
        #expect(session.commandBus.canUndo == false)  // Undo 栈重置
        #expect(session.undoRevision == oldRevision + 1)
        #expect(session.importPreview == nil)         // 载入后清预览
    }

    @Test func cancelImport_discardsPreview_withoutLoading() {
        let session = DocumentSession()
        var doc = MindMapDocument.blank(rootText: "预览稿")
        doc.root.children = [Node(text: "x")]
        session.importPreview = ImportPreviewState(
            sourceName: "a.md", document: doc, nodeCount: 2, depth: 2
        )

        session.cancelImport()

        #expect(session.importPreview == nil)
        #expect(session.model.document.root.text == "中心主题")  // 未载入，保持原文档
        #expect(session.commandBus.canUndo == false)
    }

    @Test func loadImported_resetsDocumentID() {
        let session = DocumentSession()
        let oldID = session.documentID
        var doc = MindMapDocument.blank(rootText: "新根")
        session.loadImported(doc)
        #expect(session.documentID != oldID)  // 每次载入新文档换新 docID（供自动保存配对）
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd YMindApp && xcodebuild test -project YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS' -only-testing:YMindAppTests/DocumentSessionImport`
Expected: FAIL —— `loadImported` / `ImportPreviewState` / `documentID` 未定义。

- [ ] **Step 3: 实现 `DocumentSession` 扩充**

在 `DocumentSession` 加属性（放现有 `@Published` 区附近）与方法（放 `newDocument` 附近）：

```swift
    @Published var importPreview: ImportPreviewState?
    var documentID = UUID()   // 自动保存/恢复配对用（未命名文档亦然）

    /// 载入一次导入解析出的新树为当前文档：等同「打开」语义但 fileURL=nil、isDirty=true。
    func loadImported(_ document: MindMapDocument) {
        commitEditingIfNeeded()
        model.document = document
        model.selectOnly(document.root.id)
        syncSelectionFromModel()
        commandBus.clearHistory()
        undoRevision += 1
        fileURL = nil
        lastSavedDocument = document
        isDirty = true
        documentID = UUID()
        editingId = nil
        draftText = ""
        originalEditingText = ""
        camera = Camera()
        importPreview = nil
        relayout()
        errorMessage = nil
    }

    func cancelImport() {
        importPreview = nil
    }
```

在同文件（`SearchState` 附近，类型定义区）追加：

```swift
struct ImportPreviewState: Equatable {
    let sourceName: String
    let document: MindMapDocument
    var nodeCount: Int
    var depth: Int
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2 命令
Expected: PASS（3 个测试全过）。

- [ ] **Step 5: Commit**

```bash
git add YMindApp/YMindApp/Session/DocumentSession.swift YMindApp/YMindAppTests/DocumentSessionTests.swift
git commit -m "feat: DocumentSession 导入载入（loadImported 重置 Undo）+ 预览态"
```

---

### Task 5: Shell — `DocumentWorkflow` 导入入口 + File 菜单「导入…」

**Files:**
- Modify: `YMindApp/YMindApp/YMindAppApp.swift`（`DocumentWorkflow` 增三方法 + 私有面板；`DocumentCommands` 增「导入…」子菜单）

**Interfaces:**
- Consumes: `DocumentImporterRegistry.importer(for:)`（Task 3）、`DocumentSession.loadImported/cancelImport/importPreview`（Task 4）。
- Produces: `@MainActor static func importMarkdown/importOPML/importFreeMind(_ session:)`。Task 6 浮层确认/取消按钮映射到 `loadImported`/`cancelImport`（不直接经 Workflow）。

- [ ] **Step 1: 在 `DocumentWorkflow` 增导入入口（放 `exportPNG` 之后、`confirmReplacement` 之前）**

```swift
    /// 导入入口（FR-I1/I2）：选文件 → 解析 → 暂存 importPreview（不载入），等预览确认。
    static func importMarkdown(_ session: DocumentSession) { presentImportPanel(session, extensions: ["md", "markdown"]) }
    static func importOPML(_ session: DocumentSession)     { presentImportPanel(session, extensions: ["opml"]) }
    static func importFreeMind(_ session: DocumentSession) { presentImportPanel(session, extensions: ["mm"]) }

    private static func presentImportPanel(_ session: DocumentSession, extensions: [String]) {
        guard confirmReplacement(of: session) else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url,
              let importer = DocumentImporterRegistry.importer(for: url.pathExtension) else {
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let document = try importer.parse(data)
            session.importPreview = ImportPreviewState(
                sourceName: url.lastPathComponent,
                document: document,
                nodeCount: nodeCount(of: document.root),
                depth: depth(of: document.root)
            )
        } catch ImportError.unrecognizedOutline {
            session.errorMessage = "未识别为导图大纲（缺少标题）"
        } catch ImportError.invalidXML {
            session.errorMessage = "文件不是有效的 XML 导图"
        } catch {
            session.errorMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    private static func nodeCount(of node: Node) -> Int {
        1 + node.children.reduce(0) { $0 + nodeCount(of: $1) }
    }
    private static func depth(of node: Node) -> Int {
        1 + (node.children.map { depth(of: $0) }.max() ?? 0)
    }
```

> `UTType` 已可用（文件顶部 `import UniformTypeIdentifiers`）；`.md`/`.opml`/`.mm` 一般有系统 UTType，`compactMap` 容忍解析不到的扩展名。**ImportError 的 catch 顺序：`unrecognizedOutline`/`invalidXML` 必须写在 `catch` 前**（Swift 模式匹配按序），见上。

- [ ] **Step 2: `DocumentCommands` 增「导入…」子菜单（`newItem` 组之后）**

```swift
        CommandGroup(replacing: .newItem) {
            Button("新建") {
                DocumentWorkflow.newDocument(session)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("打开…") {
                DocumentWorkflow.open(session)
            }
            .keyboardShortcut("o", modifiers: .command)

            Menu("导入…") {
                Button("Markdown…") { DocumentWorkflow.importMarkdown(session) }
                Button("OPML…") { DocumentWorkflow.importOPML(session) }
                Button("FreeMind…") { DocumentWorkflow.importFreeMind(session) }
            }
        }
```

> 若 SwiftUI `Menu` 在 `CommandGroup` 的 `Commands` 构建块内不可编译，改用平铺三项（`Divider()` 分隔）对齐原型 menu-mock 视觉。构建通过为准。

- [ ] **Step 3: 构建确认**

Run: `cd YMindApp && xcodebuild build -project YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS'`
Expected: 构建成功。

- [ ] **Step 4: Commit**

```bash
git add YMindApp/YMindApp/YMindAppApp.swift
git commit -m "feat: 导入入口 — DocumentWorkflow + File 菜单子菜单（MD/OPML/FreeMind）"
```

---

### Task 6: Shell — `ImportPreviewView` 预览浮层 + 确认/取消

**Files:**
- Create: `YMindApp/YMindApp/App/ImportPreviewView.swift`
- Modify: `YMindApp/YMindApp/ContentView.swift`（挂浮层）

**Interfaces:**
- Consumes: `session.importPreview`（Task 4）、`session.loadImported/cancelImport`（Task 4）。
- Produces: `ImportPreviewView` 无对外导出，仅内部展示与回调。Task 7 收尾验证。

- [ ] **Step 1: 创建 `ImportPreviewView.swift`**

```swift
import SwiftUI

/// 导入预览浮层：展示解析出的树（缩进列表），确认/取消。
struct ImportPreviewView: View {
    let sourceName: String
    let nodeCount: Int
    let depth: Int
    let document: MindMapDocument
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("导入预览")
                .font(.headline)
            Text("\(sourceName) · \(nodeCount) 个节点 · \(depth) 层")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ScrollView {
                indentList(document.root, depth: 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 260)
            HStack {
                Spacer()
                Button("取消") { onCancel() }
                Button("确认导入") { onConfirm() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding()
    }

    @ViewBuilder
    private func indentList(_ node: Node, depth: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Text(String(repeating: " ", count: depth * 2) + (depth == 0 ? "◎ " : "–"))
                Text(node.text)
            }
            ForEach(node.children, id: \.id) { child in
                indentList(child, depth: depth + 1)
            }
        }
    }
}
```

> `ForEach(node.children, id: \.id)`：`Node` 是 `Identifiable`（有 `id`），可 `ForEach(node.children)` 或显式 `id: \.id`。`indentList` 递归为私有 `@ViewBuilder`，SwiftUI 递归 View 无问题。

- [ ] **Step 2: `ContentView` 挂浮层（`errorMessage` 块之后，同一 ZStack 内）**

```swift
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
```

- [ ] **Step 3: 构建确认**

Run: `cd YMindApp && xcodebuild build -project YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS'`
Expected: 构建成功。

- [ ] **Step 4: 手测（对齐 PRD §6 验收 1–3）**

Run 应用，准备一个含标题+列表的 `roadmap.md`：
1. File → 导入 → Markdown… → 选文件；确认预览浮层显示根/层级/节点数（FR-I1 验收 1）。
2. 「确认导入」→ 画布呈现新文档，title 带编辑点（isDirty），可继续编辑（FR-I1）。
3. 用空文件 / 只有列表无标题的文件 → 弹「未识别为导图大纲」，当前文档不受影响（验收 2）。
4. 用 OPML / FreeMind 文件 → 层级正确；非法 XML → 报告错误且当前文档不变（验收 3）。
5. 首次确认前若当前文档脏 → 触发保存确认（`confirmReplacement` 复用）。

- [ ] **Step 5: Commit**

```bash
git add YMindApp/YMindApp/App/ImportPreviewView.swift YMindApp/YMindApp/ContentView.swift
git commit -m "feat: 导入预览浮层（确认导入/取消，展示树结构）"
```

---

### Task 7: 收尾 — 全量验证 + 边界 + 文档

**Files:**
- Verify: 全量测试、`scripts/check-boundaries.sh`。
- Modify: `docs/架构现状.md`（登记新文件）、`docs/prds/.../prd.md`（status 若仓库有惯例）。

**Interfaces:**
- Consumes: 全部前面任务。

- [ ] **Step 1: 全量构建 + 测试**

Run: `cd YMindApp && xcodebuild test -project YMindApp.xcodeproj -scheme YMindApp -destination 'platform=macOS'`
Expected: 全部测试 PASS（既有 + `MarkdownImporterTests`/`XMLImportersTests`/`DocumentImporterRegistryTests`/`DocumentSessionImportTests`）。

- [ ] **Step 2: 边界校验**

Run: `scripts/check-boundaries.sh`
Expected: 输出「依赖边界检查通过」，退出码 0。`DocumentImporter.swift`/`MarkdownImporter.swift`/`XMLImporters.swift`（Model，仅 Foundation）不违规。

- [ ] **Step 3: 登记 `docs/架构现状.md`**

在 §2.1 各层类型列追加：Model 增 `DocumentImporter`/`MarkdownImporter`/`XMLImporters`（含 OPML/FreeMind）；Session 增 `ImportPreviewState`；App 增 `ImportPreviewView`。§6 命令清单**不变**（导入不新增命令）。

- [ ] **Step 4: Commit**

```bash
git add docs/架构现状.md
git commit -m "docs: 登记导入子系统（Model 导入器 + Session 预览态 + App 浮层）"
```

---

## Self-Review 记录

- **Spec 覆盖：** §3.1（协议/错误）→ Task 1 + Task 3（注册表）；§3.2（Markdown）→ Task 1；§3.3（OPML/FreeMind）→ Task 2；§4（loadImported/预览态）→ Task 4；§1.2+§5 入口与菜单 → Task 5、6；§7 验收 → Task 6 手测 + Task 7。
- **占位符：** 无 TBD/TODO；每个代码步骤含完整可复制代码。Task 1/5 各有一处「若实现/编译有出入可调整」的**实现自由度注明**，non-placeholder（行为断言不变）。
- **类型一致性：** `ImportError`、`DocumentImporter.parse`、`MarkdownImporter`、`OPMLImporter`、`FreeMindImporter`、`DocumentImporterRegistry.importer(for:)`、`ImportPreviewState(sourceName/document/nodeCount/depth)`、`DocumentSession.loadImported(_:)/cancelImport()/documentID`、`DocumentWorkflow.importMarkdown/importOPML/importFreeMind` 在 Task 间签名一致。
- **先红后绿：** 每个 Task 的「先红」来自**该 Task 自己定义的类型未实现**，不引用后续 Task 类型，`-only-testing` 单 Task 可隔离（编译错误在 Task 内闭环）。Task 1 先红 → 实现闭绿；Task 2/3 同理，无跨 Task 编译红。