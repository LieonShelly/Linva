---
name: linva-render-text
description: Linva 的文字渲染路径（TextAtlas / TextTextureRasterizer / BranchToggleAtlas）与 Metal 文字纹理的坐标系、Retina、缓存。当修改文字绘制、文字纹理缓存、或遇到文字渲染坐标系/模糊/翻转问题时使用。
license: proprietary
---

# Linva 文字渲染（TextAtlas / Metal 纹理）

Linva 用 Metal 画文字：先用 Core Text / AppKit 把文字栅格化成位图，再上传成 Metal 纹理绘制。这条路径最容易踩「坐标系翻转」「Retina 缩放」「脏缓存」三个坑。

## 关键文件

- `Render/TextAtlas.swift` —— `TextAtlas`（节点文字缓存）、`BranchToggleAtlas`（折叠按钮文字缓存）、`TextTextureRasterizer`
- `Render/MetalRenderer.swift` —— 消费纹理绘制
- `Layout/TextMeasure.swift` —— CPU 侧量字（与栅格化同一套字体度量，必须一致）

## 核心坑与不变量

### 1. 坐标系翻转（最重要，已踩过）
`TextTextureRasterizer` 用「**翻转的 AppKit 图形上下文**栅格化文字，再把像素行翻成『首行=顶边』」上传 Metal：
- CG/AppKit 位图缓冲往往**底行在前**；
- `flipVertically(_:width:height:)` 把底行在前翻成**顶行在前**，与 Metal 纹理第 0 行一致。
- **改这段时保留行翻转**：否则文字会上下颠倒或错位。参考 `TextTextureRasterizer.flipVertically`，不要「顺手删掉」。

### 2. Retina / contentsScale
- 文字纹理按 `displayScale`（Retina scale）栅格化，位图宽高 = 逻辑尺寸 × scale。
- 坐标、命中（`CanvasHitTesting`）、纹理 UV 必须与 `contentsScale` 对齐，否则模糊或错位。

### 3. 脏缓存更新
- `TextAtlas.entries: [UUID: CacheEntry]` 按节点 id 缓存。
- **文字变更** → 该节点纹理须重建。`SetText` 命令后，Session 标记脏键 → 重布局 → 按脏键重建纹理。
- **新增缓存**：若给节点加新样式/字段且影响纹理，按脏键加入重建逻辑，避免显示旧纹理。

### 4. 度量一致
- CPU 量字（`TextMeasure`）与 GPU 栅格化（`TextTextureRasterizer`）必须用同一套字体度量，否则「布局框」和「画出来的文字」对不齐。

## 踩坑记录（改前必读）

- 文字纹理坐标系：AppKit 位图底行在前 → 必须 `flipVertically` 翻成顶行在前。**这是历史真实踩过的坑**（见 `docs/架构现状.md` §7.4「渲染文字路径已踩过坐标系坑」）。
- 改 `TextAtlas`/`TextTextureRasterizer` 后，保持回归截图/手测：缩放、Retina、改字后纹理刷新。

## 验证

- 目测：不同节点文字、编辑改字后立即刷新、折叠按钮文字正确、Retina 屏清晰不糊。
- 回归手测清单见 `docs/架构现状.md` §7.4。
