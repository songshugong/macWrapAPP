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

## 运行逻辑（简版）
- 在 Finder 图标视图中，`→` 到行尾时自动跳到下一行行首；`←` 到行首时自动跳到上一行行尾。
- 如果已在第一页第一个或最后一页最后一个图标，会做边界截断，保持不动。
- 行内普通移动尽量走 Finder 原生行为，只在跨行边界时增强。
- 仅在 Finder 前台普通窗口生效，不在桌面或其他应用中接管。
- 按住 `Option` 可临时回到原生导航。
- 文本编辑态（如重命名）会自动放行，避免干扰输入。

## 稳定性与性能策略（简版）
- 事件处理有超时预算，超时时自动放行，避免卡键。
- 网格信息有短时缓存，减少重复 AX 遍历开销。
- 内置统计计数和资源采样（CPU/内存）用于调参与排障。

## 路径级策略
在源码 `FinderWrapNavigatorSources/FinderRightArrowWrapService.swift` 里可配置：
- `wrapEnabledPathPrefixes`
- `nativeOnlyPathPrefixes`

规则：
- 命中 `nativeOnlyPathPrefixes`：强制使用 Finder 原生导航。
- `wrapEnabledPathPrefixes` 为空：默认全路径启用（除 native-only）。
- `wrapEnabledPathPrefixes` 非空：仅命中前缀目录启用增强。

## 仓库
- GitHub: https://github.com/songshugong/macWrapAPP
