# macWrapAPP

Version: **1.1**

## 中文说明

### 下载
- [直接下载 FinderWrapNavigator.app.zip](https://github.com/songshugong/macWrapAPP/raw/main/release/FinderWrapNavigator.app.zip)

### 这是什么
- 一个 macOS Finder 图标模式方向键增强工具（菜单栏应用）。
- 目标是让 Finder 的方向键体验更接近 Windows。

### 主要功能
- `→` 到行尾时自动跳到下一行开头。
- `←` 到行首时自动跳到上一行末尾。
- 长按 `←/→` 加速模式（可开关）。
- 开机启动。
- 隐藏菜单图标 / 隐藏 Dock 图标。
- 中英文界面切换。

### 安装与启动
1. 下载并解压 `FinderWrapNavigator.app.zip`。
2. 双击 `FinderWrapNavigator.app` 启动。
3. 如果提示“无法验证开发者”，右键 App -> `打开`。

### 首次权限
- 必需：辅助功能（Accessibility）。
- 可选：输入监控（Input Monitoring）。
- 说明：核心功能依赖辅助功能，输入监控不是硬性前置条件。

### 首次安装建议流程
1. 启动 App。
2. 完成“辅助功能”授权。
3. 授权成功后主界面会提示“重新启动应用”，点击一次。
4. 确认主功能已启用后开始使用。

### 无签名应用说明
- 当前发布包是无签名测试分发。
- 如果提示“已损坏”或打不开，在终端执行：

```bash
xattr -dr com.apple.quarantine /path/to/FinderWrapNavigator.app
```

---

## English

### Download
- [Download FinderWrapNavigator.app.zip](https://github.com/songshugong/macWrapAPP/raw/main/release/FinderWrapNavigator.app.zip)

### What This Is
- A macOS menu bar app that enhances Finder arrow-key navigation in icon view.
- It makes Finder behavior closer to Windows-style row wrapping.

### Key Features
- `→` at row end wraps to the first item of the next row.
- `←` at row start wraps to the last item of the previous row.
- Hold `←/→` turbo mode (toggleable).
- Launch at login.
- Hide menu bar icon / hide Dock icon.
- Chinese / English UI switch.

### Install
1. Download and unzip `FinderWrapNavigator.app.zip`.
2. Open `FinderWrapNavigator.app`.
3. If macOS says the developer cannot be verified, right-click the app and choose `Open`.

### Permissions
- Required: Accessibility.
- Optional: Input Monitoring.
- Note: Core behavior only requires Accessibility.

### First-Run Flow
1. Launch the app.
2. Grant Accessibility permission.
3. Click `Restart App` when the panel prompts after permission is granted.
4. Confirm the main feature is enabled.

### Unsigned Build Note
- The distributed package is unsigned.
- If macOS blocks it as damaged/untrusted, run:

```bash
xattr -dr com.apple.quarantine /path/to/FinderWrapNavigator.app
```
