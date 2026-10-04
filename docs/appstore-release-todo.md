# Linva (YMind) — App Store 上线 To-Do

> 本文档是上线的**唯一进度真源**（防失忆）。每完成一项即更新状态并 commit。
> 状态图例：☐ 待办 / 🔄 进行中 / ✅ 完成 / ⏸ 阻塞（含原因）
>
> 当前分支：`main`。上次提交：`83526d8`（图标 + 命名文档）。
> 工程名：`YMindApp`；对外显示名：`Linva`；Bundle ID：`com.linva.app`（已改）。

---

## 阶段 0 — 工程配置（代码可完成，预计 1 天）

| # | 项 | 状态 | 详情 / 验证 |
|---|---|---|---|
| 0.1 | 修 CFBundleDisplayName 前导空格 | ✅ | 发现真实 bug：`GENERATE_INFOPLIST_FILE=NO` 下手写 Info.plist 无 CFBundleDisplayName，Dock 显示 `YMindApp`。已加 `CFBundleDisplayName=Linva` 到 Info.plist，清掉 pbxproj 无效配置。构建产物验证 `Linva` 生效 |
| 0.2 | 补 .entitlements 文件 + 引用 | ✅ | App Sandbox=YES 但无 entitlements 文件/CODE_SIGN_ENTITLEMENTS，App Store 分发必须显式。建 `YMindApp/YMindApp.entitlements`（App Sandbox + 用户选定文件读写），pbxproj 两配置引用。codesign 验证三个 entitlement 均进签名 |
| 0.3 | 隐私清单 PrivacyInfo.xcprivacy | ✅ | 2024.5 起强制。代码检查：无 UserDefaults/@AppStorage/@SceneStorage，FileManager 仅目录枚举/创建（非时间戳/磁盘空间 API），Date() 仅存元数据 → 无 required-reason API。建 `YMindApp/YMindApp/PrivacyInfo.xcprivacy`（Tracking=false + 三个空数组，fileSystemSynchronizedGroups 自动入 bundle），构建验证清单在 Resources |
| 0.4 | 补 NSHumanReadableCopyright | ✅ | Info.plist 原无此键。补 `© 2026 lieoncx`（暂用 git 作者名，可在 0.5 一起定） |
| 0.5 | Bundle ID 规范化 | ✅ | `com.YMindApp` → `com.linva.app`（主 target 两配置），测试 target 跟随 `com.linva.app.Tests`/`.UITests`。代码零硬编码（Info.plist 用变量），文档与决策清单同步更新。**用户已拍板** |

## 阶段 1 — 账号与元数据（用户操作，代码帮不了）

| # | 项 | 状态 | 详情 |
|---|---|---|---|
| 1.1 | Apple Developer 账号注册 | ☐ | $99/年。**阻塞一切签名/上传** |
| 1.2 | App Store Connect 创建 App 记录 | ☐ | 需要 Bundle ID、显示名、类目（生产力/效率） |
| 1.3 | 隐私政策页 | 🔄 | 已写 `docs/privacy-policy.md`（无数据收集/无网络/无第三方 SDK，如实声明）。**待用户**：GitHub 仓库 Settings → Pages → 从 `docs/` 发布，得到可访问 URL（App Store Connect 必填链接） |
| 1.4 | 隐私营养标签（App Store Connect 问卷） | ☐ | 不收集数据→选「不收集」即可，与 0.3 清单一致 |

## 阶段 2 — 体验补全（影响过审与首用）

| # | 项 | 状态 | 详情 |
|---|---|---|---|
| 2.1 | 首次启动欢迎（示例导图/欢迎窗口） | ☐ | 空画布直开显"未完成"。欢迎窗口或自动开示例导图 |
| 2.2 | About / 关于窗口 | ☐ | App 菜单 About（HIG 常见检查项）。SwiftUI 设置/关于 |
| 2.3 | 千节点级性能自测 | ☐ | Metal 画布大文档卡顿审核员会实测。生成 1000+ 节点文档实测流畅度 |

## 阶段 3 — 构建与提交

| # | 项 | 状态 | 详情 |
|---|---|---|---|
| 3.1 | Archive + 公证 | ☐ | 需要签名证书（阶段 1 后）。xcodebuild archive + notarytool |
| 3.2 | 元数据：截图 + 描述 + 关键词 | ☐ | 截图规格（App Store Connect）、中文描述、关键词 |
| 3.3 | 上传 + 提交审核 | ☐ | Xcode Organizer 或 Transporter |

---

## 审核风险备忘

- 2.4.5 Mac App Store：必须沙盒（0.2 补 entitlements）、遵循 macOS HIG
- 2.3.1 元数据一致：App 名/描述/截图对齐 Linva
- 1.1/2.1 完整可用：无未完成 UI、无崩溃路径
- 2.5 软件要求：无私有 API（代码检查为公开 API，风险低）
- 性能：千节点实测（2.3）

## 决策待定

- [x] 0.5 Bundle ID：`com.linva.app`（已拍板并实施）
- [x] 0.4 版权署名：`© 2026 lieoncx`（已拍板）
- [ ] 2.1 欢迎方式：欢迎窗口 or 自动建示例导图 or 两者？
- [ ] 1.1 开发者账号是否已注册？（决定阶段 1 是否可开始）

## 已完成记录

- 2026-10-04: 图标 10 尺寸写入 AppIcon.appiconset 并构建验证（commit 83526d8）
- 2026-10-04: 阶段0 0.2-0.4（entitlements/隐私清单/版权）commit 6b12fb2
- 2026-10-04: 阶段0 0.5 Bundle ID → com.linva.app（commit 待 0.5 验证后提交）
