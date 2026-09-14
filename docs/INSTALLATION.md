# 安装、更新与一次授权体验 / Installation and permission continuity

## 用户体验目标

已按用户决定采用 GitHub 编译应用分发，不要求 Apple 开发者会员或公证。流程为：下载应用 ZIP → 解压并放入固定可写位置 → 按 macOS 提示允许打开 → 首次允许辅助功能 → 开始使用。用户不需要源码、Xcode、证书脚本或钥匙串配置。首次打开未公证应用的说明见 [直接安装指南](INSTALL_APP.md)。

macOS 决定权限是否继续有效。这里的“一次授权”指同一台 Mac、同一用户、稳定签名身份与安装位置、没有人为撤销或系统重置的正常升级流程；不能绕过首次授权，也不能承诺跨设备或身份变化后仍免授权。

本机已验证：从 1.2.4 更新到 1.2.5，迁移到用户 Applications 目录，以及同一签名的再次更新后，辅助功能/按键发布权限都继续有效。没有运行 `tccutil reset`，没有删除授权条目或更换证书。

## 本机安装与更新

```bash
./scripts/build-app.sh
# 先从菜单退出正在运行的目标应用，再安装。
./scripts/install-app.sh
open "$HOME/Applications/ClipboardBoard.app"
```

安装脚本默认目标为 `$HOME/Applications/ClipboardBoard.app`，也可显式传入来源和目标 `.app` 路径。

- 先验证来源签名和 bundle ID。
- 更新时，来源应用必须满足目标旧应用的身份要求；不重新签名、不创建证书、不重置授权。
- 目标仍运行时拒绝替换，避免“磁盘新版、进程旧版”。
- 先在目标目录暂存并验证，再替换；失败时尽量恢复原包。
- 已有数据目录不覆盖。首次安装仅在目标没有数据目录时迁移来源旁的数据。
- 数据一直位于安装目录旁的 `ClipboardBoardData`，需要当前用户可写。

## 发布者流程

当前默认：先构建并验收，再运行 `./scripts/package-app.sh`，它仅打包已验收的应用，不重建、不重新签名。生成 `ClipboardBoard-v版本-macos-架构.zip` 及其 `.sha256` 文件；将两者附加到对应 GitHub Release。包内只包含应用、安装说明和 LICENSE，不包含真实数据或签名材料。


从 1.7.0 开始，`.github/workflows/release.yml` 在推送标签后只创建包含源码 ZIP 和校验文件的 Release 草稿。必须准备并上传签名更新包、`appcast.xml` 和手动安装包，核对全部附件后才公开发布，避免自动更新读取到不完整的最新版。发布者可使用 `scripts/publish-release.sh` 完成上传、远端哈希校验和最终发布；详见 [自动更新与发版](AUTO_UPDATE.md)。签名私钥不上传到 GitHub。

当前使用 `ClipboardBoard Local Development` 固定自签名身份，已提供编译好的下载包，**不声称经过 Apple 公证**。以下公证流程仅供将来有需要时选择，并非 GitHub 发版前置条件。

准备好发布者证书和已配置的 notarytool Keychain profile 后：

```bash
CODE_SIGN_IDENTITY="Developer ID Application: Publisher Name (TEAMID)" \
NOTARY_PROFILE="your-existing-notary-profile" \
./scripts/package-release.sh
```

脚本依次编译本机架构、固定应用标识、设置构建编号、Developer ID 签名（hardened runtime + timestamp）、提交公证、staple、校验 Gatekeeper，最后生成带版本与架构的 ZIP 和 SHA-256。公证或验证失败时不会发布候选包。该脚本不修改本机开发包。

发布前仍须：在另一台 Mac 验证首次授权、同身份更新、系统登录项、应用搬移和安装失败恢复。证书、凭据、开发私钥及真实剪贴板历史不得进入仓库或分发 ZIP。

## English

The chosen distribution path is a compiled, self-signed, unnotarized app on GitHub. End users extract and install it at a stable writable location, follow macOS first-open checks, and grant Accessibility access. They do not need source code, Xcode, certificates, or Apple Developer membership. `package-app.sh` packages the already tested app with installation instructions and a license, preserving its original signature. macOS retains control of permission continuity; revocation, system resets, different users/devices, or signing-identity changes may require consent again.

`install-app.sh` verifies the source, checks continuity against an existing destination signature, refuses to replace a running destination, stages the bundle, and preserves existing destination data. It does not re-sign the app or reset permissions.

`package-release.sh` is a publisher-only Developer ID/hardened-runtime/notarization/stapling workflow. A production identity and notarization profile are not available on this machine, so no notarized release is claimed. The current local development builds retained both existing paste permissions across upgrade, stable-path installation, and a subsequent update.

## Apple 参考资料

- [Code identity and designated requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [SMAppService registration](https://developer.apple.com/documentation/servicemanagement/register())
