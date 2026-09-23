# YMind v1 合并前最终修复报告

日期：2026-09-24  
分支：`feat/ymind-v1`

## 状态

全分支终审列出的 4 项 Important 已全部修复。

## 修复内容

1. **保存、替换或关闭前提交编辑草稿**
   - 将 `editingId`、`draftText` 和原始文案提升到 `DocumentSession`。
   - 新增 `startEditing(_:)`、`commitEditingIfNeeded()`、`cancelEditing()`。
   - `save`、`saveAs`、`newDocument`、`load`、替换确认和窗口关闭流程均先提交草稿；文案变化通过 `SetText` 进入命令历史并参与 dirty 判断。

2. **⌘Q 退出确认**
   - 增加 `NSApplicationDelegate.applicationShouldTerminate`。
   - 复用文档替换确认流程；取消时返回 `.terminateCancel`，保存或不保存后返回 `.terminateNow`。

3. **折叠数量徽章**
   - Metal 绘制顺序调整为“边 → 节点底色 → 文字 → 折叠徽章 → 选中描边”。
   - 仅对 `collapsed && hiddenCount > 0` 的可见节点绘制强调色胶囊徽章和白色数量文本。
   - 增加 `CollapseBadge` 可测试渲染数据 helper，以及快照到徽章数据的单元测试。

4. **Security-scoped access 生命周期**
   - `SecurityScopedAccess` 在读写前调用 `startAccessingSecurityScopedResource()`。
   - 仅在 start 成功后持有或停止 scope；失败路径不再错误调用 stop。
   - 移除调用方虚假的 `securityScopeAlreadyActive: true`。
   - 替换文件时，新文件 I/O 成功后才释放旧 scope；失败时保留旧文件 scope。

## 验证

- Debug 构建：通过。
- `xcodebuild test ... -only-testing:YMindAppTests`：通过。
- 单元测试：35 项全部通过。
- IDE linter：本次修改文件无诊断。

## 剩余关注

- 未执行真实沙盒授权下的人工 Open/Save Panel 往返测试；安全作用域的调用顺序与成对释放已由注入式单元测试覆盖。
- 未执行折叠徽章的人工视觉验收；显示条件、隐藏数量和渲染数据生成已由单元测试覆盖。
- 终审列出的 Minor 未扩展处理。
