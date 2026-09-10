# 安装 ClipboardBoard / Install ClipboardBoard

## 中文

这是已经编译好的 macOS 应用，不需要源码、Xcode、命令行工具或 Apple 开发者会员。

1. 解压下载的 ZIP。`macos-arm64` 版本适用于 Apple Silicon（M1/M2/M3/M4/M5 等）；不适用于 Intel Mac。
2. 把 `ClipboardBoard.app` 拖到个人主目录下的 `Applications` 文件夹（`~/Applications`，没有时可新建），放好后再打开。这个目录需要你能够写入，因为历史会保存在应用旁。
3. 本应用使用固定自签名证书，**未经 Apple 公证**。首次打开如果提示无法验证开发者，请先尝试打开一次，再到「系统设置 → 隐私与安全性」点击「仍要打开」，确认打开。仅在确认下载自本项目且文件完整时执行；若提示恶意软件或文件损坏，请停止并反馈，不要关闭系统安全保护。
4. 按应用提示，在「系统设置 → 隐私与安全性 → 辅助功能」中允许 ClipboardBoard。随后正常复制，用 **Option+V** 打开历史，方向键选择，**回车或双击**粘贴。

更新前先退出旧版，用新 `ClipboardBoard.app` 替换同一位置的旧应用。保留旁边的 `ClipboardBoardData` 数据文件夹，不需要导入签名证书或运行签名脚本。相同签名和路径有助于保留授权，但 macOS 仍可能在更新、权限被撤销或系统重置时要求确认。

最低目标系统为 macOS 13；本发布包在 Apple Silicon、macOS 26.6.2 上验收，其他系统版本尚未逐一验证。

校验文件为同一 Release 下的 `ClipboardBoard-v1.2.5-macos-arm64.zip.sha256`。包内不含任何用户的剪贴板历史、签名私钥或账号凭据。

[Apple 关于打开未公证应用的说明](https://support.apple.com/zh-cn/102445)

## English

This ZIP contains a compiled macOS app. You do not need source code, Xcode, command-line tools, or an Apple Developer membership.

1. Extract the ZIP. The `macos-arm64` build is for Apple Silicon Macs (M-series), not Intel Macs.
2. Drag `ClipboardBoard.app` into `Applications` inside your home folder (`~/Applications`; create it if needed), then open it there. The location must be writable because history is stored beside the app.
3. The app uses a stable self-signed certificate and **is not notarized by Apple**. If macOS cannot verify the developer, first attempt to open the app, then use **System Settings → Privacy & Security → Open Anyway** and confirm. Only proceed if you trust the download and have verified its integrity. Stop if macOS reports malware or damage; do not disable system-wide protections.
4. Grant ClipboardBoard **Accessibility** access when prompted. Copy normally, open history with **Option+V**, select with arrow keys, and paste with **Return or double-click**.

To update, quit the old version and replace the app at the same location. Keep the adjacent `ClipboardBoardData` folder. Do not import certificates or run signing scripts. A stable signature and location help preserve permission, but macOS may still request confirmation after updates, revocation, or system resets.

The minimum deployment target is macOS 13. This package was validated on Apple Silicon with macOS 26.6.2; other versions have not all been tested. Check the companion `.zip.sha256` file from the same Release. No user history, signing private keys, or account credentials are included.

[Apple instructions for opening unnotarized apps](https://support.apple.com/en-us/102445)
