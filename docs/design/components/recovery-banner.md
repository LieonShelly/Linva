# Linva 组件规格 — 恢复横幅（RecoveryBannerView）

> 层级：**SwiftUI 壳**。启动扫描到上次未保存草稿时，顶部横幅提示恢复/忽略。色值引用 `design-tokens.md`，动效引用 `motion-tokens.md`。

---

## 1. 结构

| 属性 | 值 |
|------|-----|
| 位置 | 画布顶部居中横幅（搜索条同层） |
| 卡面 | `sem.color.surface.overlay` + `prim.radius.card` (10pt) |
| 内容 | 警告三角 + 标题 + 摘要（文档名 · 源文件 · 最近自动保存 · N 处修改）+ 忽略/恢复 |

---

## 2. 状态表

| 元素 | 默认 | hover |
|------|------|-------|
| 警告三角 | `sem.color.search`（amber 警示） | — |
| 标题 | `font.headline` | — |
| 摘要 | `caption` + `text.secondary` | — |
| 忽略（丢弃草稿） | 默认按钮 | — |
| 恢复更改 | `borderedProminent` | — |

---

## 3. 行为

| 事件 | 行为 |
|------|------|
| 出现 | 启动 `scanForRecovery` 扫描到最新副本 |
| 恢复 | `restoreDraft` → 载入草稿，标记 dirty |
| 忽略 | `discardDraft` → 清副本，载最近正式版 |
| 只提示最新 | 多副本只展示最新 |

---

## 4. 动效

| 事件 | token |
|-------|-------|
| 出现 | `motion.duration.medium` 自顶滑入（`motion.easing.out`） |

---

## 5. 无障碍 / 合规

- `.accessibilityLabel("检测到上次未保存的更改")`。
- 两按钮可键盘触达（Tab + Enter）。

---

## 变更记录
| 日期 | 说明 |
|------|------|
| 2026-10-02 | 首版：恢复横幅 + 状态/行为/动效，锚定 `RecoveryBannerView` / `DocumentWorkflow` |
