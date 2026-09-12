# 更新日志 / Changelog

版本按新到旧排列。以下描述各版本当时的变更；当前行为以 [中文说明](README.md) / [English README](README.en.md) 为准。

Versions are listed newest first. These entries describe changes at each release; see the READMEs for current behavior.

## 1.4.0

- 新增自定义全局快捷键：主动录制、系统/排他注册冲突检查、保存失败保留旧组合、恢复默认和重启恢复。菜单与历史提示显示当前组合。
- Add configurable global shortcuts with explicit recording, system/exclusive registration checks, transactional saving, default restoration, restart persistence, and updated UI labels.
- 117 项 Swift 测试、8 项流程测试通过，实机及接口边界见 [快捷键验收](docs/CUSTOM_SHORTCUT.md)。

## 1.3.1

- 完整文本预览新增“JSON 格式化”和“查看原文”，只调整展示，不改剪贴板或历史。保持数字精度、重复键、顺序及转义；后台处理，失败提示行列并保留原文。
- Add JSON formatting and exact original-text restoration to full previews. Preserve numeric lexemes, duplicate keys, order, and escapes; format in the background and report errors without clipboard/history writes.
- 105 项 Swift 测试、8 项流程测试通过；完整采集与界面链路已实测，见 [JSON 格式化验收](docs/JSON_PREVIEW.md)。

## 1.3.0

- 新增可配置悬浮全文预览、选区复制入历史、图片原图缩放和独立置顶拖动；Esc 恢复原选择，搜索空格和预览回车不误触粘贴。
- 按 History、Preview、Preferences、WindowChrome 拆分窗口及交互职责，旧设置默认启用 1 秒悬浮。
- Add configurable full-content hover previews, explicit selection copying, original-image zoom and movable pinned windows. Preserve search input and selection, and isolate preview keys from paste actions.
- Separate history, preview, preferences and shared window chrome; retain legacy settings compatibility.
- 验收 / Acceptance: [完整预览记录](docs/PREVIEW.md) · [发布说明 / Release notes](docs/releases/v1.3.0.md)。

## 1.2.5

- 根据文本编辑中的实机失败补齐回车快捷键/搜索框命令路径，保护输入法组词并忽略长按重复；用户已在构建 2F555699 上确认回车正常粘贴一次。
- Add Return handling through AppKit key-equivalent and search-field command routes after a TextEdit report, preserving IME composition and ignoring key repeats. The user confirmed a single successful Return paste in TextEdit on build 2F555699.

- 历史上限统一为 1–50 条，旧设置自动收敛；满额后逐条淘汰最早复制的不同内容。
- 数据格式版本化，新增重试、损坏文件留存后重建；恢复尊重本次删除和清空，未来版本格式只读保护。
- 新增固定路径安装、发布者签名公证脚本，以及运行版本/构建哈希验收前置检查。
- 登录项缺失时允许用户重新注册，不再将开关永久禁用；本机重新注册及关闭已实测。
- 完整执行 81 项 Swift 测试和 8 项构建/安装流程测试。实机状态详见验收文档，未覆盖场景不标为通过。

- Enforce a 1–50 entry limit, normalize legacy settings, and evict the oldest distinct copy one at a time.
- Version data files and add retry/archive-and-rebuild recovery that respects session deletions and protects future formats.
- Add stable-path installation, publisher signing/notarization scripts, and process/build identity checks before acceptance.
- Allow retrying a missing login registration; successful registration and disabling were verified locally.
- Run all 81 Swift tests and 8 build/install workflow tests. See the acceptance record for live evidence and remaining scenarios.

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
