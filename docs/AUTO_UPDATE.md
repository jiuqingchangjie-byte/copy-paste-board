# 自动更新与发版

## 用户体验

1.7.0 源码已集成 Sparkle 2.10.0。菜单中提供“检查更新…”、“自动检查更新”和“自动下载并安装更新”，四种应用语言均有译文；Sparkle 自身窗口使用 macOS 语言。

- 默认自动检查，通常每 24 小时检查一次；不会在每次打开历史面板时联网。
- 默认不自动安装。用户开启后，Sparkle 在后台下载，通常在退出应用时安装；长时间不退出时可提示安装。需要系统授权的安装不保证静默完成。
- 关闭自动检查仍可手动检查；自动下载选项随 Sparkle 的可用状态启用/禁用，保留原有选择。偏好由 Sparkle 的 UserDefaults 管理，应用不在每次启动时写回默认值。
- 只更新 `.app`。历史、收藏、自定义存储及位置指针位于应用外；退出前继续执行既有持久化，存储迁移未结束时拒绝退出，交互更新会等待存储操作完成后继续重启。
- 无网络、无可用更新、用户取消或签名不正确时，不把未验证的应用替换进安装目录。
- 1.6.1 及更早版本没有更新器，必须手动安装首个包含此功能的版本一次。

## 更新来源与信任

`SUFeedURL` 固定为：

```
https://github.com/jiuqingchangjie-byte/copy-paste-board/releases/latest/download/appcast.xml
```

清单作为 Release 附件提供，无需独立服务或 GitHub Pages。每次发布必须同时包含签名清单及其指向的版本专属更新包。不能删除旧客户端仍可能正在下载的历史 Release 附件。当前通道分发 arm64，最低 macOS 13。

`SUPublicEDKey` 保存 Ed25519 公钥。私钥只在发布者钥匙串中，Sparkle 账户名为 `com.local.clipboardboard`；不会写入 Git、应用包或 GitHub Actions。必须保管这份私钥，日后签名更新使用同一账户，不能因找不到密钥就重新生成并替换公钥。Apple 固定代码签名身份同样继续保留，不通过更新器重置辅助功能权限。

启用 `SUVerifyUpdateBeforeExtraction` 和 `SURequireSignedFeed`；签名清单验证失败不设置自动过期放行。发布工具会校验公钥匹配、版本、下载地址、包内容、字节长度、应用源码指纹和 Sparkle 的实际签名。

仅更新检查和软件下载会访问 GitHub（含下载重定向/CDN）。不上传剪贴板内容，`SUEnableSystemProfiling=false`。普通网络请求仍包含标准 User-Agent 等必要 HTTP 信息。

## 构建与准备附件

SwiftPM 固定 Sparkle 2.10.0，依赖提交和二进制校验和由 `Package.resolved` 与上游包清单锁定。`build-app.sh` 保留 framework 符号链接、从内向外签名 helpers/framework，并附带 Sparkle 许可证。运行源指纹会阻止同版本旧构建被拿来发布。

```bash
./scripts/test.sh
python3 -m unittest discover -s Tests/Scripts -p 'test_*.py'
./scripts/build-app.sh
# 按 docs/ACCEPTANCE.md 核对运行身份并完成本轮验收。
./scripts/package-app.sh
./scripts/prepare-update.sh
```

`prepare-update.sh` 只打包已构建应用，不重建。使用 `generate_appcast` 自动生成签名清单与嵌入的更新说明，避免手工编辑签名 XML。输出为：

```
dist/ClipboardBoard-v1.7.0-macos-arm64.zip
dist/ClipboardBoard-v1.7.0-macos-arm64.zip.sha256
dist/updates/v1.7.0/ClipboardBoard-v1.7.0-update-arm64.zip
dist/updates/v1.7.0/appcast.xml
dist/updates/v1.7.0/UPDATE-SHA256SUMS.txt
```

手动安装 ZIP 含说明和许可证；自动更新 ZIP 中仅含 `ClipboardBoard.app`。不在生成清单后重新打包 ZIP，否则签名和字节数会失效。

## 公开发布

更新版本及内部递增版本号，提交发布说明与代码，推送对应的附注标签。GitHub Actions 现在只创建包含源码和校验文件的 **草稿**，不会把只有源码的版本设为 Latest。

完成已授权的提交和标签推送后，发布者可以执行（需要已登录的 GitHub CLI）：

```bash
./scripts/publish-release.sh
```

脚本要求工作区干净、本地标签和远端标签均指向当前提交；对照线上 Latest，发行版本和内部构建号必须同时增加，更新公钥保持一致。准备安装包、签名更新包和清单，将七个附件上传到草稿；验证所有附件上传完成且 GitHub 返回的 SHA-256 与本地一致后，才执行公开发布并设为 Latest。已公开的同版本拒绝覆盖；发生失败时保留草稿，修正后重试。

没有 `gh` 时可在浏览器上传上述五个附件到自动创建的草稿，加上已有源码 ZIP 和 `SHA256SUMS.txt`，确认全部完成再发布。不要先发布草稿再补附件。

## 2026-09-14 验收证据

| 项目 | 结果 |
| --- | --- |
| Swift 全量回归 | 146 项、19 个套件通过，包括设置保留、检查并发保护、初始化失败、等待存储后恢复重启 |
| Python 流程回归 | 17 项通过，包括构建流程保护、元数据/版本/URL/包内容及远端附件大小、状态、哈希检查，以及版本递增和更新公钥连续性 |
| 依赖打包 | Release 构建成功，framework、helpers 和 app 严格签名检查通过 |
| 手动更新实机 | 隔离旧版 `1.7.0-acceptance` → `1.7.1-acceptance`，检查、下载、校验、替换、重启全部完成；新进程路径、版本、构建 ID、哈希匹配候选包 |
| 最新版 | 升级后再次检查，显示“您使用的就是最新版” |
| 篡改清单 | 修改已签名清单中的版本文案，实际更新器报签名校验失败并拒绝更新，原版本继续可用 |
| 篡改安装包 | Sparkle 官方工具验证原更新 ZIP 成功；对等长副本修改一个字节后，原 EdDSA 签名验证失败 |
| 偏好持久化 | 通过菜单启用检查及自动下载，退出重启后两项 UserDefaults 仍为 true |
| 后台自动更新实机 | 隔离旧版 `1.7.1-automatic` 未点击检查/安装即请求清单并下载；正常退出后磁盘更新为 `1.7.2-automatic`，再次启动核对完整运行身份通过 |
| 数据与权限 | 测试历史标记、上限 37、英语选择仍在；收藏 SQLite 和位置指针字节保持；两次升级后的辅助功能与模拟按键权限均为 true |

实机测试先核对运行身份；HTTP 仅用于临时 localhost 测试源，正式配置始终 HTTPS。测试版本及更新源只在 `.build/update-acceptance`，不会放进正式 Release。结束后关闭测试服务并恢复原已发布应用。没有进行真实 GitHub 公开发布或从公网跨机器更新，本轮也没有验证断电、磁盘满、用户主动撤销权限等场景。

上述记录为发布前的隔离验收。正式更新源随完整的 [1.7.0 Release](https://github.com/jiuqingchangjie-byte/copy-paste-board/releases/tag/v1.7.0) 开放，不通过改写旧 Release 提前开放。

## English overview

Sparkle 2.10.0 is pinned through SwiftPM. Automatic checks default to on; automatic download and installation is opt-in. Preferences are owned by Sparkle, not mirrored in app data. Updates preserve adjacent history, favorites, and custom storage configuration. Relaunch waits for storage operations; a relocation prevents premature app termination.

The stable feed is the `appcast.xml` asset of the latest GitHub release. Feeds and archives must be EdDSA-signed; verification precedes extraction. Signing keys stay in the publisher's Keychain. Update networking does not transmit clipboard content or system profiling data.

Tag pushes prepare a draft only. `scripts/publish-release.sh` uploads and checks every asset before making the release public and latest. Manual upgrade, background download/install-on-quit, invalid feed rejection, preference persistence, data retention and permission continuity were tested with isolated local fixtures before publication. The production feed becomes available with the complete 1.7.0 release; users on 1.6.1 and earlier must install it manually once.

Official references: [Setup](https://sparkle-project.org/documentation/), [Programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/), [Settings](https://sparkle-project.org/documentation/customization/), [Publishing](https://sparkle-project.org/documentation/publishing/).
