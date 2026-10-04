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
| 1.3 | 隐私政策页 | ✅ | 已部署到 GitHub Pages：**正式 URL `https://lieonshelly.github.io/YMind/`**（HTTP 200，浅/深色自适应）。用 `gh-pages` 孤儿分支隔离发布，只含 `index.html`，`/docs` 内部文档不公开。内容 `docs/privacy-policy.md` 同步。提交 `d21e38f` |
| 1.4 | 隐私营养标签（App Store Connect 问卷） | ☐ | 不收集数据→选「不收集」即可，与 0.3 清单一致 |

## 阶段 2 — 体验补全（影响过审与首用）

| # | 项 | 状态 | 详情 |
|---|---|---|---|
| 2.1 | 首次启动欢迎（欢迎窗口） | ⏸ | 方案已拍板（欢迎窗口）。**用户要求搁置**：后续单独做设计稿后再实现 |
| 2.2 | About / 关于窗口 | ✅ | SwiftUI 默认 App 菜单自带「About Linva」系统标准面板。发现 `CFBundleName=$(PRODUCT_NAME)=YMindApp` 导致面板显示旧名 → Info.plist 改 `CFBundleName=Linva`（不影响可执行文件名，由 CFBundleExecutable 决定）。运行验证：菜单栏全变 Linva，面板显示 Linva + Version 1.0 (1) + © 2026 lieoncx + 图标 |
| 2.3 | 千节点级性能自测 | ✅ | 新增基准测试 `LargeDocumentPerformanceTests`（radial+logic 各 1 用例，1011 节点，阈值 <2s）。Release(-O) 实测：radial 0.556s / logic 0.572s 全量布局。真实加载 1011 节点 `.ymind`（578KB）验证：窗口标题正确、蓝色根节点居中 + 左右各 5 主干×100 子节点、垂直堆叠无重叠、连线清晰；滚动/平移/缩放后无崩溃/残影，进程稳定 0% CPU 空闲 |

## 阶段 3 — 构建与提交

| # | 项 | 状态 | 详情 |
|---|---|---|---|
| 3.1 | Archive + 公证 | ☐ | 需要签名证书（阶段 1 后）。xcodebuild archive + notarytool |
| 3.2 | 元数据：截图 + 描述 + 关键词 | 🔄 | 已产出 `docs/appstore-metadata.md`（描述/关键词/截图规格+4张建议画面+提交自查）。截图规格已按 Apple 官方确认（16:10，1280×800/1440×900/2560×1600/2880×1800，1-10张，.jpeg/.jpg/.png，无 alpha）。**截图流程已打通**：运行 app 载入示例导图 → `screencapture` → `sips` 裁窗口并转 1440×900 JPEG 无 alpha → 素材示例 `docs/appstore-screenshots/linva-screenshot-01.jpg`。**最终截图待 2.1 欢迎窗口设计落定后统一重拍**（避免与最终 UI 不一致） |
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
- [x] 2.1 欢迎方式：欢迎窗口（已拍板；**实现搁置**等设计稿）
- [ ] 1.1 开发者账号是否已注册？（决定阶段 1 是否可开始）

## 已完成记录

- 2026-10-04: 图标 10 尺寸写入 AppIcon.appiconset 并构建验证（commit 83526d8）
- 2026-10-04: 阶段0 0.2-0.4（entitlements/隐私清单/版权）commit 6b12fb2
- 2026-10-04: 阶段0 0.5 Bundle ID → com.linva.app（commit 170a65a）
- 2026-10-04: 阶段1 1.3 隐私政策初稿（commit f72d558）
- 2026-10-04: 阶段1 1.3 隐私政策部署到 GitHub Pages（gh-pages 分支 d21e38f，URL https://lieonshelly.github.io/YMind/）
- 2026-10-04: 阶段2 2.2 About 面板修复（commit 5abd9ab）
- 2026-10-04: 阶段2 2.3 千节点性能自测（基准测试 + 真实渲染验证）
- 2026-10-04: 阶段3 3.2 元数据文档 + 截图流程打通（示例素材，最终截图待 2.1 设计稿）
