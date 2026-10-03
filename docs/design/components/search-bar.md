# YMind — Component Spec: SearchBar（搜索浮层）

> SwiftUI 壳层浮层，顶部居中。现状：`SearchBar.swift`，`regularMaterial` 圆角条。
> 引用 token：`--c-search-*`、`--s-focus-ring`、`--s-search-hit`。

---

## 1. 结构

```
[ 🔍 搜索主题…          |  3 / 12  |  ▲  ▼  ✕ ]
```

| 元素 | 规格 |
|---|---|
| 输入框 | 宽 240pt，pill 圆角，聚焦 ring |
| 计数 | `3 / 12`，等宽数字，次级色 |
| 上一项 ▲ / 下一项 ▼ | 无匹配禁用 |
| 关闭 ✕ | Esc |

---

## 2. 状态表

| 状态 | 行为 |
|---|---|
| **默认** | 聚焦输入框，光标就位 |
| **无匹配** | 计数 `0 / 0`，上下箭头禁用；画布无高亮 |
| **有命中** | 计数高亮，当前命中节点画布**居中**（`centerCamera`，Metal 层 `--m-spring-gentle` 补间），命中节点琥珀高亮 `--s-search-hit` |
| **切换 ▲▼** | Enter/Shift+Enter / 按钮，命中循环 |
| **关闭** | Esc / ✕ / 失焦，清搜索态 |

---

## 3. 行为细则

1. 打开：⌘F / 菜单「搜索…」，`onAppear` 聚焦。
2. 查询变化：优先留在仍匹配的当前节点，否则回落第一个匹配（现状逻辑，保持）。
3. 命中节点居中动画在 **Metal 相机**层做补间（`motion-tokens.md §4.6`），SwiftUI 只改 `session.search` 状态。
4. 关闭后：高亮清除，画布回到原视图位置。

---

## 4. 无障碍

- 输入框有 label「搜索主题」。
- 计数有 `accessibilityLabel`（现状已有）。
- 上下箭头有 label 与快捷键提示（⇧Enter / Enter）。
