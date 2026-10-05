---
name: linva-codec-version
description: Linva 的 .linva 文件格式与版本升迁规则（LinvaCodec）。当修改节点数据结构、新增字段、或涉及 .linva 序列化/反序列化/兼容性时使用。
license: proprietary
---

# Linva 文件格式与版本升迁（LinvaCodec）

`.linva` 是 versioned JSON。改任何会影响序列化的结构，必须先看本技能，否则老文件会打不开或数据被静默污染。

## 关键文件

- `Model/MindMapDocument.swift` —— 文档模型与 `currentVersion`
- `Model/LinvaCodec.swift` —— encode / decode / sanitize
- `Model/Node.swift`、`Model/Side.swift` —— 节点字段

## 版本与兼容规则

1. **`currentVersion` 是硬校验**：`decode` 先做版本迁移（见规则 2），再 `guard doc.version == MindMapDocument.currentVersion else { throw .unsupportedVersion }`。**不在迁移链内的版本直接拒绝**。所以：
   - 每改一次序列化 schema，**必须递增 `currentVersion`**。
   - **已在迁移链内的旧版本**（如 v1）由内置迁移抬到当前版本，**不再抛** `unsupportedVersion`；**迁移链外的版本**（如未来未知版本）仍抛 `unsupportedVersion` —— 需要你为它写下一段迁移。
   - **现状：`currentVersion == 6`（v2 新增 `Node.fill` 节点填色；v3 新增 `Node.image` / `imagePixelSize` 节点内嵌图片；v4 将 `text`/`image` 重构为 `ContentBlock[] blocks` 图文流；v5 新增文档属性 `layout: LayoutKind` 布局字段，`.radial`/`.logic`；v6 根节点折叠由单值 `collapsed` 改为左右侧独立 `collapsedLeft`/`collapsedRight`）**。v1→v2、v2→v3、v3→v4、v4→v5、v5→v6 迁移**均已内置**：旧文件无 `fill` 视为无填色、无 `image`/`imagePixelSize` 视为无图、v3 及以下无 `blocks` 由 Node 解码器 fallback 合成块、v4→v5 迁移 `layout` 缺省 `.radial`（解码器 `decodeIfPresent ?? .radial`，零拒绝）、**v5→v6 迁移：根 `collapsed=true` → 两侧独立 `collapsedLeft=collapsedRight=true` 并清空遗留 `collapsed`**。改 schema 仍须递增到 7，并按下面的流程写 v6→v7 迁移。
2. **改 schema 的正确流程**：
   - 递增 `currentVersion`；
   - 新增字段在 `MindMapDocument`/`Node` 上加（`Codable` 合成，缺省要有合理默认值）；
   - **必须写迁移**：旧版本 decode 后要能把老数据抬到新 schema。`decode` 用 `if doc.version == 1 { doc.version = 2 }`、`if doc.version == 2 { doc.version = 3 }` 逐版本迁移（v1→v2、v2→v3、v3→v4、v4→v5、v5→v6 已内置：旧文件无 `fill` 视为无填色、无 `image`/`imagePixelSize` 视为无图、v3→v4 仅抬版本号由 Node 解码器 fallback 合成块、v4→v5 仅抬版本号 `layout` 缺省 `.radial`、v5→v6 根折叠单值迁两侧独立并清遗留），新增时在末尾追加下一段 `if` 迁移，逐版本抬到 `currentVersion`。
   - 迁移要在 `decode` 里、`sanitize` 前完成。
3. **`sanitize` 的 `side` 消毒（重要不变量）**：`side` 字段**只允许出现在根节点下第一层**。`sanitize` 会：
   - 强制 `root.side = nil`；
   - 对根的直接子节点保留 `side`；
   - 对更深层的节点，若带 `side` 则置 `nil` 并**记入 warnings**（`"深层节点的 side 字段已被忽略（节点 id: ...）"`）。
   - 新增字段若也有类似「只许出现在特定层级」的约束，参照此模式处理。
   - **文档属性不属节点层级消毒范围**：`layout` 是文档级字段，`sanitize` 重建文档时须**显式保留**（`MindMapDocument(version:root:layout:)`），否则逻辑图文档消毒后被重置为辐射。
4. **decode 的 warnings**：`decode(_:warnings:)` 会收集消毒产生的警告。新增消毒逻辑时，把用户可感知的降级写进 warnings，不要静默吞掉。
5. **encode 前也 sanitize**：`encode` 调 `sanitize(document)`，保证写出的文件层级合法（例如根带 side 时不会写脏）。encode 用 `[.prettyPrinted, .sortedKeys]`（稳定输出，利于 diff）。

## 新增字段的检查清单

- [ ] 递增 `currentVersion`
- [ ] 加字段（含 Codable 缺省默认值）
- [ ] 写旧版本 → 新版本的迁移
- [ ] 若字段有层级约束（类似 side），在 sanitize 里消毒 + warnings
- [ ] 文档级字段（如 `layout`）：`sanitize` 重建文档时须保留（`MindMapDocument(version:root:layout:)`），防消毒后丢失
- [ ] encode 前 sanitize 确保不写出非法状态
- [ ] 更新 `CodecTests`（编解码往返、版本拒绝、side 消毒、迁移）
- [ ] 同步更新 `docs/架构现状.md`（字段表）与本技能

## 验证

`CodecTests` 覆盖：`encode→decode` 往返一致、`unsupportedVersion` 拒绝、深层 side 消毒、迁移正确。改完跑 `xcodebuild test`。
