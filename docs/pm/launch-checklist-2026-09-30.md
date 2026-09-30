# YMind 上线就绪清单（App Store 1.0 提交）

**日期：** 2026-09-30
**范围：** 迁移闭环（导入/自动保存恢复落地；PDF 导出已移除）后，以「App Store 公开上架 v1.0」为目标的上线就绪评估。
**结论：** 功能完整度已够 1.0；卡上架的是工程合规与元数据，不是功能。P0 ×2 + P1 ×2 + 策略 ×1，其余为迭代项。

---

## A. 已具备（证据）

| 项 | 状态 | 证据 |
|----|------|------|
| 沙盒 | ✅ | `project.pbxproj`：`ENABLE_APP_SANDBOX = YES` + `ENABLE_USER_SELECTED_FILES = readwrite` |
| 文件类型关联（双击 `.ymind` 打开） | ✅ | `Info.plist`：`CFBundleDocumentTypes`（Editor/Owner）+ `UTExportedTypeDeclarations`（com.ymind.document / ymind 扩展名） |
| 安全作用域文件访问 | ✅ | `DocumentSessionTests.securityScopedAccess_startsBeforeOperation_andBalancesOwnedScopes` |
| 数据容错（损坏文件不崩） | ✅ | Codec 版本校验 + v1→v2 迁移；`bad version` 单测 |
| 无账号 / 无网络 | ✅ 优势 | 纯本地单文档工具，审核面最小；无数据收集项 |
| 版本号 | ✅ | `MARKETING_VERSION = 1.0` / `CURRENT_PROJECT_VERSION = 1` |
| 首启体验 | ✅ | 默认「中心主题」文档，评审员打开即可操作，无空状态 |
| 自动化测试 | ✅ | 12 单测文件 + UI 测试（`YMindAppTests/`、`YMindAppUITests/`） |
| 撤销/重做 | ✅ | 12 个可逆命令走 `CommandBus` |

## B. P0 — 会被拒 / 无法提交（必须做）

| # | 项 | 说明 |
|---|----|------|
| 1 | **AppIcon 是空的** | `AppIcon.appiconset/Contents.json` 只有尺寸声明、**无 filename**——整套图标未填充。提交必拒（元数据不完整）。需设计全套 16–512@2x + App Store 1024 |
| 2 | **隐私清单缺失** | 全工程无 `*.xcprivacy`。若使用 required reason API（UserDefaults / 文件时间戳 / 磁盘空间）必须声明，否则提交被拦。当前 app 代码未见 UserDefaults，但自动保存增量（FR-S1）写临时副本/可能读时间戳——开发时同步补清单 |
| 3 | **App Store Connect 元数据** | 截图（1280×800，需真实画布内容；当前 UI 朴素，建议 1.0 前做一次画布呈现美化再截）、描述、关键词、隐私政策 URL、年龄分级、出口合规——提交表单必填 |

## C. P1 — 强烈建议（不拒但风险 / 口碑 / 迭代）

| # | 项 | 说明 |
|---|----|------|
| 4 | **崩溃稳定性实测** | 审核指南 2.1：评审员手动测到崩溃直接拒。重点压测：Metal 渲染路径、PNG 离屏导出、500–1000 节点大图、连续 Undo |
| 5 | **崩溃上报** | 无 Crashlytics/自建上报 = 1.0 盲飞，后续迭代质量无数据。可先加最小实现或上架后补（但建议 1.0 前） |
| 6 | **部署目标决策** | `MACOSX_DEPLOYMENT_TARGET = 26.4` 只支持 macOS 26——排除所有 ≤25 用户。建议降到 macOS 15/16 并全链路回归（覆盖独立开发者主流盘子） |
| 7 | **签名 / entitlements 确认** | 无 `.entitlements` 文件（Xcode 26 构建设置自动注入）；`REGISTER_APP_GROUPS = YES` 存疑（app 无 App Groups 需求）。开发端确认：签名实际注入的 entitlements 含沙盒 + 用户文件读写，否则提交被拦 |

## D. P2 — 迭代项（不拦 1.0）

| # | 项 | 说明 |
|---|----|------|
| 8 | 无障碍 | Metal 画布无 accessibility 树；SwiftUI 壳默认部分可达。评审风险中低，口碑影响大 |
| 9 | 关于 / 帮助菜单 | macOS 惯例；`NSHumanReadableCopyright` 为空 |
| 10 | UI 打磨 | 当前功能优先朴素样式；影响截图卖相与转化，1.0 前至少做「截图用的画布呈现」美化 |

## 建议的 1.0 定义

**迁移闭环（开发终端进行中） + P0 全部 + P1 的 4、7 + 6（降部署目标）**；P1 的 5（崩溃上报）与 D 项列入 1.1。

---

## 修订记录

| 日期 | 说明 |
|------|------|
| 2026-09-30 | 初稿：基于工程实况（pbxproj / Info.plist / AppIcon / 单测）+ App Store 审核要求评估 |