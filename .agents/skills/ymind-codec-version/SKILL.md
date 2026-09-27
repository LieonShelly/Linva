---
name: ymind-codec-version
description: YMind 的 .ymind 文件格式与版本升迁规则（YMindCodec）。当修改节点数据结构、新增字段、或涉及 .ymind 序列化/反序列化/兼容性时使用。
license: proprietary
---

# YMind 文件格式与版本升迁（YMindCodec）

`.ymind` 是 versioned JSON。改任何会影响序列化的结构，必须先看本技能，否则老文件会打不开或数据被静默污染。

## 关键文件

- `Model/MindMapDocument.swift` —— 文档模型与 `currentVersion`
- `Model/YMindCodec.swift` —— encode / decode / sanitize
- `Model/Node.swift`、`Model/Side.swift` —— 节点字段

## 版本与兼容规则

1. **`currentVersion` 是硬校验**：`decode` 里 `guard doc.version == MindMapDocument.currentVersion else { throw .unsupportedVersion }`。**版本不符直接拒绝**，不会尝试自动迁移。所以：
   - 每改一次序列化 schema，**必须递增 `currentVersion`**。
   - 老版本文件会抛 `unsupportedVersion` —— 这是预期行为，需要你提供迁移。
2. **改 schema 的正确流程**：
   - 递增 `currentVersion`；
   - 新增字段在 `MindMapDocument`/`Node` 上加（`Codable` 合成，缺省要有合理默认值）；
   - **必须写迁移**：旧版本 decode 后要能把老数据抬到新 schema。当前代码没有迁移层，需要你加（参考 `decode` 的 `switch doc.version` 分支，逐版本迁移到 `currentVersion`）。
   - 迁移要在 `decode` 里、`sanitize` 前完成。
3. **`sanitize` 的 `side` 消毒（重要不变量）**：`side` 字段**只允许出现在根节点下第一层**。`sanitize` 会：
   - 强制 `root.side = nil`；
   - 对根的直接子节点保留 `side`；
   - 对更深层的节点，若带 `side` 则置 `nil` 并**记入 warnings**（`"深层节点的 side 字段已被忽略（节点 id: ...）"`）。
   - 新增字段若也有类似「只许出现在特定层级」的约束，参照此模式处理。
4. **decode 的 warnings**：`decode(_:warnings:)` 会收集消毒产生的警告。新增消毒逻辑时，把用户可感知的降级写进 warnings，不要静默吞掉。
5. **encode 前也 sanitize**：`encode` 调 `sanitize(document)`，保证写出的文件层级合法（例如根带 side 时不会写脏）。encode 用 `[.prettyPrinted, .sortedKeys]`（稳定输出，利于 diff）。

## 新增字段的检查清单

- [ ] 递增 `currentVersion`
- [ ] 加字段（含 Codable 缺省默认值）
- [ ] 写旧版本 → 新版本的迁移
- [ ] 若字段有层级约束（类似 side），在 sanitize 里消毒 + warnings
- [ ] encode 前 sanitize 确保不写出非法状态
- [ ] 更新 `CodecTests`（编解码往返、版本拒绝、side 消毒、迁移）
- [ ] 同步更新 `docs/架构现状.md`（字段表）与本技能

## 验证

`CodecTests` 覆盖：`encode→decode` 往返一致、`unsupportedVersion` 拒绝、深层 side 消毒、迁移正确。改完跑 `xcodebuild test`。
