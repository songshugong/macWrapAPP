# macWrapAPP

[直接下载 FinderWrapNavigator.app.zip](https://github.com/songshugong/macWrapAPP/raw/main/release/FinderWrapNavigator.app.zip)

Finder 图标模式方向键增强工具（macOS 菜单栏应用）。

## 这是一个什么补丁
- 让 Finder 在图标模式下的方向键更接近 Windows 体验。
- `→` 到行尾时自动跳下一行开头。
- `←` 到行首时自动跳上一行末尾。
- 支持长按 `←/→` 加速模式（可开关）。

## 无签名补丁下载
- 当前提供的是无签名版本（测试分发）。
- 下载地址：`release/FinderWrapNavigator.app.zip`
- 直接点击上方下载链接即可。

## 安装与启动
1. 下载并解压 `FinderWrapNavigator.app.zip`。
2. 双击 `FinderWrapNavigator.app` 启动。
3. 如果系统提示“无法验证开发者”，请右键 App -> `打开`。

## 如果提示“已损坏”或打不开
在终端执行（把路径换成你自己的 App 路径）：

```bash
xattr -dr com.apple.quarantine /path/to/FinderWrapNavigator.app
```

然后再次双击打开。

## 首次权限
首次运行必需：
- 辅助功能（Accessibility）

可选（部分环境可能会提示）：
- 输入监控（Input Monitoring）

说明：当前版本核心功能依赖辅助功能；输入监控不是硬性前置条件。

## 使用说明
- 启用主功能：开启 Finder 方向键换行增强。
- 长按加速模式：长按 `←/→` 时切换更快。
- 开机启动：开机自动运行。
- 支持中英文切换。

## 待办事项
- [x] 优化“隐藏 Dock 图标”开关：开启时自动同步清理 Dock 的 `recent-apps` 条目并刷新 Dock，避免残留图标。
- [x] 在主界面显示权限状态：明确标识“辅助功能（必需）/输入监控（可选）”是否到位。
