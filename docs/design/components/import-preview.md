# YMind — Component Spec: ImportPreview（导入预览浮层）

> SwiftUI 浮层，导入 MD/OPML/FreeMind 后确认。现状：`ImportPreviewView.swift`。
> 引用 token：`--c-popover-*`。

---

## 1. 结构

```
┌──────────────────────────┐
│ 导入预览                  │
│ source.md · 24 个节点 · 3 层 │
│ ┌──────────────────────┐ │
│ │ ◎ 根主题             │ │
│ │   – 子主题           │ │
│ │   – 子主题           │ │
│ └──────────────────────┘ │
│              [取消] [确认导入] │
└──────────────────────────┘
```

| 元素 | 规格 |
|---|---|
| 面板 | `.regularMaterial` + `--p-panel`，圆角 14，阴影 `--p-shadow-2` |
| 标题 | headline |
| 元信息 | subheadline 次级色 |
| 树预览 | 缩进列表，高度上限 260pt，可滚动 |
| 动作 | 取消 / 确认导入（borderedProminent） |

---

## 2. 状态表

| 状态 | 行为 |
|---|---|
| **预览** | 展示解析树，未改磁盘 |
| **确认** | `loadImported`（清命令栈、标记脏、重置 documentID） |
| **取消** | 关闭，不载入 |
| **解析失败** | 不弹浮层，画布顶显示错误横幅（现状 `errorMessage`） |

---

## 3. 行为细则

1. 导入不覆盖磁盘既有 `.ymind`（现状）。
2. 确认/取消均不入命令栈（导入是整体替换，非可逆命令）。
3. 大树：树预览 ScrollView，节点行懒渲染（现状 `IndentNodeView` 递归）。
