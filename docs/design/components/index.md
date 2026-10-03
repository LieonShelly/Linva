# YMind — 组件规格索引

> 每个组件一个文件，含状态表 + 精确行为 + 语义 token 引用。
> 与 `design-tokens.md`、`motion-tokens.md`、`prototype/design/*.html` 配套。

## 画布（Metal 层）
| 组件 | 文件 | 说明 |
|---|---|---|
| 节点卡 | `node.md` | 默认/hover/选中/剪切/放置/填色 状态表 |
| 分叉控件（折叠） | `branch-toggle.md` | 折叠展开控件 |
| 画布与边 | `canvas.md` | 系统原生底、连线、相机、框选 |

## 壳层（SwiftUI / AppKit）
| 组件 | 文件 | 说明 |
|---|---|---|
| 工具条 | `toolbar.md` | 收敛高频 + 溢出低频 |
| 右键菜单 | `context-menu.md` | **新增项**（现状缺失） |
| 搜索浮层 | `search-bar.md` | 顶部居中搜索条 |
| 编辑浮层 | `node-editor-overlay.md` | 就地文字/图片编辑 |
| 填色组 | `fill-swatches.md` | 5 色 + 清除 |
| 导入预览 | `import-preview.md` | 导入确认浮层 |
| 恢复横幅 | `recovery-banner.md` | 崩溃恢复提示 |
| 菜单栏 | `menu-bar.md` | HIG 标准菜单结构 |

## 状态表速查（跨组件）

| 状态 | 通用视觉 | 动效 |
|---|---|---|
| hover | 浅底 / 描边 accent | `--m-fast` |
| active/pressed | 下压 | `--m-fast` |
| disabled | opacity .35 | — |
| selected/focus | accent 描边 + 泛光 | `--m-base` |
| destructive hover | danger 混底 | `--m-fast` |

---

## 待办 / 缺口（设计阶段发现）

- [ ] **右键菜单**：现状完全缺失，HIG 强制，需新增（`context-menu.md`）。
- [ ] **菜单栏**：核对现有 `DocumentCommands` 是否含全部 HIG 标准菜单（App/File/Edit/View/Window/Help）。
- [ ] **在线画布底色**：补暗色动态色 `#171719`（亮色已是系统灰），见 `design-tokens.md §6`。
