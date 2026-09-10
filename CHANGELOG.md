# 更新日志 / Changelog

版本按新到旧排列。以下描述各版本当时的变更；当前行为以 [中文说明](README.md) / [English README](README.en.md) 为准。

Versions are listed newest first. These entries describe changes at each release; see the READMEs for current behavior.

## 1.2.4

- 尝试恢复原窗口和输入焦点，优先执行目标应用原生粘贴命令。
- 辅助功能与按键发布为独立可用路径；菜单禁用或动作结果不确定时不重复发送。
- 增加粘贴诊断。基线为 69 项 Swift 测试、4 项构建流程测试；完整跨应用实机验收待完成。

- Attempt to restore the original window and input focus, preferring the target application's native Paste command.
- Support independent Accessibility and keyboard-event permission paths; avoid duplicate delivery for disabled or uncertain menu actions.
- Add paste diagnostics. Baseline: 69 Swift tests and 4 build workflow tests; full cross-application validation remains pending.

## 1.2.3

- 登录自启改为原生开关，显示实际状态、等待批准状态和失败提示，并同步系统外部修改。

- Replace the launch-at-login item with a native switch showing actual state, pending approval, and failures; reflect external system-setting changes.

## 1.2.2

- 构建改用固定签名身份，拒绝临时签名；缺失或意外更换身份时保留现有应用包。
- 已有应用时，启动脚本不再触发重新构建。

- Require a stable signing identity and reject ad-hoc signing; preserve the existing app when the identity is missing or unexpectedly changes.
- Launch existing app bundles without rebuilding.

## 1.2.1

- 普通历史只按配置条数淘汰，移除旧的 32 MiB 总容量淘汰限制。
- 历史和设置迁移至应用旁的 `ClipboardBoardData`，增加打开数据目录入口。

- Evict normal history by configured entry count, removing the former 32 MiB aggregate eviction limit.
- Migrate history and settings to `ClipboardBoardData` beside the app; add an action to open the data directory.

## 1.2.0

- 面板调整为 340 × 490，支持拖动标题区域并保存位置，修复圆角裁剪。

- Resize the panel to 340 × 490, persist the position after header dragging, and fix rounded-corner clipping.

## 1.1.1

- 无权限或目标不可用时，回车和双击明确报告未粘贴，不再降级为只复制。

- Report unavailable pasting when permissions or the target are missing, instead of silently turning Return or double-click into copy-only actions.

## 1.1

- 粘贴前等待按键释放、恢复目标应用；权限变化、应用退出、焦点切换或新的复制可取消等待操作。
- 增加登录自启；双击以实际点击记录为准。

- Wait for key release and restore the target app before pasting; cancel pending work after permission changes, target exit, focus changes, or a new copy.
- Add launch at login and make double-click use the actual clicked entry.
