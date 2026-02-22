# macWrapAPP

Finder 图标模式方向键增强工具（macOS 菜单栏应用）。

## 功能
- 图标模式下 `→` 到行尾自动换到下一行行首。
- 图标模式下 `←` 到行首自动换到上一行行尾。
- 长按 `←/→` 可选加速模式（默认关闭，可在控制面板启用）。
- 仅在 Finder 普通窗口生效，带有超时放行与异常保护。
- 提供运行统计（命中率、放行率、失败率、资源占用）。

## 项目结构
- `Package.swift`：SwiftPM 项目定义。
- `FinderWrapNavigatorSources/FinderWrapNavigatorMain.swift`：应用入口、菜单与控制面板。
- `FinderWrapNavigatorSources/FinderRightArrowWrapService.swift`：方向键增强核心逻辑。
- `FINDER_WRAP_NAVIGATOR.md`：补充说明文档。

## 本地构建
```bash
cd /Users/songzihan/Documents/mac换行APP
swift build -c release
```

## 预构建 APP（可直接使用）
- 包路径：`release/FinderWrapNavigator.app.zip`
- 解压后得到：`FinderWrapNavigator.app`
- 双击即可运行（首次可能需要在系统设置中授权权限）

## 运行
```bash
cd /Users/songzihan/Documents/mac换行APP
swift run
```

## 首次权限
首次运行时，macOS 可能请求以下权限：
- 辅助功能（Accessibility）
- 输入监控（Input Monitoring）

请在系统设置中授权后重启应用。

## 使用说明
- 主功能开关：启用/停用换行增强。
- 加速模式开关：启用后长按方向键时增强切换频率。
- 开机启动：写入/移除 `~/Library/LaunchAgents/com.finderwrap.navigator.autostart.plist`。
- 支持中英文界面切换，设置会持久化保存。

## 仓库
- GitHub: https://github.com/songshugong/macWrapAPP
