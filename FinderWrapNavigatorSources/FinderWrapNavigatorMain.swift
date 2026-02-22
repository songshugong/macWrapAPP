import AppKit
import Darwin

private enum AppLanguage: String {
    case zhHans = "zh-Hans"
    case en = "en"
}

private enum LKey {
    case menuOpenPanel
    case menuEnable
    case menuDisable
    case menuTurbo
    case menuLaunchAtLogin
    case menuHideMenuIcon
    case menuHideDesktopIcon
    case menuLanguage
    case menuLanguageChinese
    case menuLanguageEnglish
    case menuPrintStats
    case menuQuit
    case tooltipReady
    case tooltipRunning
    case tooltipStopped
    case statsTitle
    case alertOk
    case permissionTitle
    case permissionBody
    case permissionOpenSettings
    case permissionLater
    case startupFailed
    case panelTitle
    case panelSubtitle
    case panelMainFeature
    case panelTurbo
    case panelLaunchAtLogin
    case panelHideMenuIcon
    case panelHideDesktopIcon
    case panelPrintStats
    case panelQuit
    case panelDeveloperPrefix
    case panelLanguage
}

private enum L10n {
    static func text(_ key: LKey, _ language: AppLanguage) -> String {
        switch (language, key) {
        case (.zhHans, .menuOpenPanel): return "打开主界面"
        case (.zhHans, .menuEnable): return "启用"
        case (.zhHans, .menuDisable): return "停用"
        case (.zhHans, .menuTurbo): return "长按←/→加速模式"
        case (.zhHans, .menuLaunchAtLogin): return "开机启动"
        case (.zhHans, .menuHideMenuIcon): return "隐藏菜单图标"
        case (.zhHans, .menuHideDesktopIcon): return "隐藏桌面图标"
        case (.zhHans, .menuLanguage): return "语言"
        case (.zhHans, .menuLanguageChinese): return "中文"
        case (.zhHans, .menuLanguageEnglish): return "English"
        case (.zhHans, .menuPrintStats): return "打印统计信息"
        case (.zhHans, .menuQuit): return "退出"
        case (.zhHans, .tooltipReady): return "Finder 方向键换行补偿"
        case (.zhHans, .tooltipRunning): return "FinderWrap 已启用"
        case (.zhHans, .tooltipStopped): return "FinderWrap 已停用"
        case (.zhHans, .statsTitle): return "FinderWrap 统计信息"
        case (.zhHans, .alertOk): return "确定"
        case (.zhHans, .permissionTitle): return "需要辅助功能权限"
        case (.zhHans, .permissionBody): return "请在“系统设置 -> 隐私与安全性 -> 辅助功能”中允许 FinderWrapNavigator。"
        case (.zhHans, .permissionOpenSettings): return "打开设置"
        case (.zhHans, .permissionLater): return "稍后"
        case (.zhHans, .startupFailed): return "启动失败"
        case (.zhHans, .panelTitle): return "FinderWrap 控制中心"
        case (.zhHans, .panelSubtitle): return "图标模式方向键增强"
        case (.zhHans, .panelMainFeature): return "启用主功能"
        case (.zhHans, .panelTurbo): return "长按←/→加速模式"
        case (.zhHans, .panelLaunchAtLogin): return "开机启动"
        case (.zhHans, .panelHideMenuIcon): return "隐藏菜单图标"
        case (.zhHans, .panelHideDesktopIcon): return "隐藏桌面图标"
        case (.zhHans, .panelPrintStats): return "打印统计"
        case (.zhHans, .panelQuit): return "退出"
        case (.zhHans, .panelDeveloperPrefix): return "开发者"
        case (.zhHans, .panelLanguage): return "语言"

        case (.en, .menuOpenPanel): return "Open Control Panel"
        case (.en, .menuEnable): return "Enable"
        case (.en, .menuDisable): return "Disable"
        case (.en, .menuTurbo): return "Hold ←/→ Turbo"
        case (.en, .menuLaunchAtLogin): return "Launch At Login"
        case (.en, .menuHideMenuIcon): return "Hide Menu Bar Icon"
        case (.en, .menuHideDesktopIcon): return "Hide Dock Icon"
        case (.en, .menuLanguage): return "Language"
        case (.en, .menuLanguageChinese): return "Chinese"
        case (.en, .menuLanguageEnglish): return "English"
        case (.en, .menuPrintStats): return "Print Runtime Stats"
        case (.en, .menuQuit): return "Quit"
        case (.en, .tooltipReady): return "Finder arrow-wrap enhancer"
        case (.en, .tooltipRunning): return "FinderWrap enabled"
        case (.en, .tooltipStopped): return "FinderWrap disabled"
        case (.en, .statsTitle): return "FinderWrap Runtime Stats"
        case (.en, .alertOk): return "OK"
        case (.en, .permissionTitle): return "Accessibility Permission Required"
        case (.en, .permissionBody): return "Allow FinderWrapNavigator in System Settings -> Privacy & Security -> Accessibility."
        case (.en, .permissionOpenSettings): return "Open Settings"
        case (.en, .permissionLater): return "Later"
        case (.en, .startupFailed): return "Startup Failed"
        case (.en, .panelTitle): return "FinderWrap Control Center"
        case (.en, .panelSubtitle): return "Arrow-key enhancement for icon view"
        case (.en, .panelMainFeature): return "Enable Main Feature"
        case (.en, .panelTurbo): return "Hold ←/→ Turbo"
        case (.en, .panelLaunchAtLogin): return "Launch At Login"
        case (.en, .panelHideMenuIcon): return "Hide Menu Bar Icon"
        case (.en, .panelHideDesktopIcon): return "Hide Dock Icon"
        case (.en, .panelPrintStats): return "Print Stats"
        case (.en, .panelQuit): return "Quit"
        case (.en, .panelDeveloperPrefix): return "Developer"
        case (.en, .panelLanguage): return "Language"
        }
    }
}

@main
enum FinderWrapNavigatorMain {
    private static let appDelegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = appDelegate
        app.run()
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let service = FinderRightArrowWrapService()
    private let launchAtLoginManager = LaunchAtLoginManager()
    private let singleInstanceGuard = SingleInstanceGuard()
    private let launchAtLoginQueue = DispatchQueue(label: "com.finderwrap.navigator.launchAtLogin")
    private let preferences = AppPreferences()
    private var currentLanguage: AppLanguage = .zhHans
    private var controlPanelController: ControlPanelWindowController?
    private var hideMenuBarIcon = false
    private var hideDockIcon = true
    private var statusItem: NSStatusItem?
    private var openPanelItem: NSMenuItem?
    private var toggleItem: NSMenuItem?
    private var turboToggleItem: NSMenuItem?
    private var launchAtLoginItem: NSMenuItem?
    private var hideMenuBarIconItem: NSMenuItem?
    private var hideDockIconItem: NSMenuItem?
    private var quitItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard singleInstanceGuard.acquire() else {
            NSApplication.shared.terminate(nil)
            return
        }

        let startupState = preferences.loadOrInitializeDefaults()
        currentLanguage = startupState.language
        service.setRightArrowTurboEnabled(startupState.turboEnabled)
        hideMenuBarIcon = startupState.hideMenuBarIcon
        hideDockIcon = startupState.hideDockIcon
        applyInterfaceVisibility()
        configureControlPanel()

        if startupState.mainEnabled {
            startServiceIfPossible()
        }

        showControlPanelWithStartupFailsafe()
        updateToggleTitle()
    }

    func applicationWillTerminate(_ notification: Notification) {
        singleInstanceGuard.release()
    }

    @objc
    private func toggleEnabled() {
        setMainFeatureEnabled(!service.isRunning)
    }

    @objc
    private func toggleRightArrowTurboMode() {
        setTurboEnabled(!service.isRightArrowTurboEnabled())
    }

    @objc
    private func toggleLaunchAtLogin() {
        setLaunchAtLoginEnabled(!launchAtLoginManager.isEnabled)
    }

    @objc
    private func openControlPanel() {
        showControlPanel(forceActivate: true)
    }

    @objc
    private func toggleHideMenuBarIcon() {
        setHideMenuBarIconEnabled(!hideMenuBarIcon)
    }

    @objc
    private func toggleHideDockIcon() {
        setHideDockIconEnabled(!hideDockIcon)
    }

    @objc
    private func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc
    private func openInputMonitoringSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc
    private func printStatsReport() {
        let report = service.runtimeReport(reason: "menu")
        print(report)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = t(.statsTitle)
        alert.informativeText = report
        alert.addButton(withTitle: t(.alertOk))
        alert.runModal()
    }

    @objc
    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func startServiceIfPossible() {
        do {
            try service.start()
            updateToggleTitle()
        } catch FinderRightArrowWrapService.StartError.notTrusted {
            showPermissionAlert()
            updateToggleTitle()
        } catch {
            showGenericError(error)
            updateToggleTitle()
        }
    }

    private func setMainFeatureEnabled(_ enabled: Bool) {
        preferences.setMainEnabled(enabled)
        if enabled {
            startServiceIfPossible()
        } else if service.isRunning {
            service.stop()
            updateToggleTitle()
        } else {
            updateToggleTitle()
        }
    }

    private func setTurboEnabled(_ enabled: Bool) {
        service.setRightArrowTurboEnabled(enabled)
        preferences.setTurboEnabled(enabled)
        updateToggleTitle()
    }

    private func setLaunchAtLoginEnabled(_ enabled: Bool) {
        launchAtLoginQueue.async { [weak self] in
            guard let self else { return }
            var operationError: Error?

            do {
                if enabled {
                    try self.launchAtLoginManager.enable()
                } else {
                    try self.launchAtLoginManager.disable()
                }
            } catch {
                operationError = error
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.updateToggleTitle()
                if let operationError {
                    self.showGenericError(operationError)
                }
            }
        }
    }

    private func setHideMenuBarIconEnabled(_ hidden: Bool) {
        hideMenuBarIcon = hidden
        preferences.setHideMenuBarIcon(hideMenuBarIcon)
        applyInterfaceVisibility()
        updateToggleTitle()
    }

    private func setHideDockIconEnabled(_ hidden: Bool) {
        hideDockIcon = hidden
        preferences.setHideDockIcon(hideDockIcon)
        applyInterfaceVisibility()
        updateToggleTitle()
    }

    private func setLanguage(_ language: AppLanguage) {
        guard currentLanguage != language else { return }
        currentLanguage = language
        preferences.setLanguage(language)
        updateToggleTitle()
    }

    private func applyInterfaceVisibility() {
        NSApp.setActivationPolicy(hideDockIcon ? .accessory : .regular)
        configureStatusItem(visible: !hideMenuBarIcon)
    }

    private func configureStatusItem(visible: Bool) {
        if visible {
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.button?.title = ""
                item.button?.imagePosition = .imageOnly
                item.button?.toolTip = t(.tooltipReady)

                let menu = NSMenu()

                let openPanel = NSMenuItem(title: t(.menuOpenPanel), action: #selector(openControlPanel), keyEquivalent: "")
                openPanel.target = self
                menu.addItem(openPanel)
                openPanelItem = openPanel

                menu.addItem(.separator())

                let toggle = NSMenuItem(title: t(.menuEnable), action: #selector(toggleEnabled), keyEquivalent: "")
                toggle.target = self
                menu.addItem(toggle)
                toggleItem = toggle

                let turboToggle = NSMenuItem(
                    title: t(.menuTurbo),
                    action: #selector(toggleRightArrowTurboMode),
                    keyEquivalent: ""
                )
                turboToggle.target = self
                menu.addItem(turboToggle)
                turboToggleItem = turboToggle

                let launchAtLoginToggle = NSMenuItem(
                    title: t(.menuLaunchAtLogin),
                    action: #selector(toggleLaunchAtLogin),
                    keyEquivalent: ""
                )
                launchAtLoginToggle.target = self
                menu.addItem(launchAtLoginToggle)
                launchAtLoginItem = launchAtLoginToggle

                menu.addItem(.separator())

                let hideMenu = NSMenuItem(
                    title: t(.menuHideMenuIcon),
                    action: #selector(toggleHideMenuBarIcon),
                    keyEquivalent: ""
                )
                hideMenu.target = self
                menu.addItem(hideMenu)
                hideMenuBarIconItem = hideMenu

                let hideDock = NSMenuItem(
                    title: t(.menuHideDesktopIcon),
                    action: #selector(toggleHideDockIcon),
                    keyEquivalent: ""
                )
                hideDock.target = self
                menu.addItem(hideDock)
                hideDockIconItem = hideDock

                menu.addItem(.separator())
                let quit = NSMenuItem(title: t(.menuQuit), action: #selector(quitApp), keyEquivalent: "q")
                quit.target = self
                menu.addItem(quit)
                quitItem = quit

                item.menu = menu
                statusItem = item
            }
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
            openPanelItem = nil
            toggleItem = nil
            turboToggleItem = nil
            launchAtLoginItem = nil
            hideMenuBarIconItem = nil
            hideDockIconItem = nil
            quitItem = nil
        }
    }

    private func configureControlPanel() {
        let panel = ControlPanelWindowController(
            language: currentLanguage,
            iconProvider: { [weak self] in
                self?.statusIcon(isEnabled: self?.service.isRunning ?? false)
            }
        )

        panel.onMainFeatureChanged = { [weak self] enabled in
            self?.setMainFeatureEnabled(enabled)
        }
        panel.onTurboChanged = { [weak self] enabled in
            self?.setTurboEnabled(enabled)
        }
        panel.onLaunchAtLoginChanged = { [weak self] enabled in
            self?.setLaunchAtLoginEnabled(enabled)
        }
        panel.onHideMenuBarIconChanged = { [weak self] hidden in
            self?.setHideMenuBarIconEnabled(hidden)
        }
        panel.onHideDockIconChanged = { [weak self] hidden in
            self?.setHideDockIconEnabled(hidden)
        }
        panel.onLanguageChanged = { [weak self] language in
            self?.setLanguage(language)
        }
        panel.onPrintStats = { [weak self] in
            self?.printStatsReport()
        }
        panel.onQuit = {
            NSApplication.shared.terminate(nil)
        }

        controlPanelController = panel
    }

    private func showControlPanel(forceActivate: Bool) {
        guard let controlPanelController else { return }
        controlPanelController.showWindow(nil)
        if forceActivate {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showControlPanelWithStartupFailsafe() {
        showControlPanel(forceActivate: true)
        if hideMenuBarIcon && hideDockIcon {
            // If both entry points are hidden, re-open once to avoid an unreachable app state.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.showControlPanel(forceActivate: true)
            }
        }
    }

    private func t(_ key: LKey) -> String {
        L10n.text(key, currentLanguage)
    }

    private func updateToggleTitle() {
        openPanelItem?.title = t(.menuOpenPanel)
        toggleItem?.title = service.isRunning ? t(.menuDisable) : t(.menuEnable)
        turboToggleItem?.title = t(.menuTurbo)
        turboToggleItem?.state = service.isRightArrowTurboEnabled() ? .on : .off
        launchAtLoginItem?.title = t(.menuLaunchAtLogin)
        launchAtLoginItem?.state = launchAtLoginManager.isEnabled ? .on : .off
        hideMenuBarIconItem?.title = t(.menuHideMenuIcon)
        hideMenuBarIconItem?.state = hideMenuBarIcon ? .on : .off
        hideDockIconItem?.title = t(.menuHideDesktopIcon)
        hideDockIconItem?.state = hideDockIcon ? .on : .off
        quitItem?.title = t(.menuQuit)
        statusItem?.button?.title = ""
        statusItem?.button?.image = statusIcon(isEnabled: service.isRunning)
        statusItem?.button?.toolTip = t(.tooltipReady)
        statusItem?.button?.toolTip = service.isRunning
            ? t(.tooltipRunning)
            : t(.tooltipStopped)
        controlPanelController?.updateState(
            mainFeatureEnabled: service.isRunning,
            turboEnabled: service.isRightArrowTurboEnabled(),
            launchAtLoginEnabled: launchAtLoginManager.isEnabled,
            hideMenuBarIcon: hideMenuBarIcon,
            hideDockIcon: hideDockIcon
        )
        controlPanelController?.updateLanguage(currentLanguage)
        controlPanelController?.updateIcon(statusIcon(isEnabled: service.isRunning))
    }

    private func statusIcon(isEnabled: Bool) -> NSImage? {
        let symbolName = isEnabled ? "square.grid.3x3.fill" : "square.grid.3x3"
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "FinderWrap") else {
            return nil
        }
        image.isTemplate = true
        return image
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = t(.permissionTitle)
        alert.informativeText = t(.permissionBody)
        alert.addButton(withTitle: t(.permissionOpenSettings))
        alert.addButton(withTitle: t(.permissionLater))
        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    private func showGenericError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = t(.startupFailed)
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

}

private final class ControlPanelWindowController: NSWindowController {
    var onMainFeatureChanged: ((Bool) -> Void)?
    var onTurboChanged: ((Bool) -> Void)?
    var onLaunchAtLoginChanged: ((Bool) -> Void)?
    var onHideMenuBarIconChanged: ((Bool) -> Void)?
    var onHideDockIconChanged: ((Bool) -> Void)?
    var onLanguageChanged: ((AppLanguage) -> Void)?
    var onPrintStats: (() -> Void)?
    var onQuit: (() -> Void)?

    private var language: AppLanguage
    private let iconProvider: () -> NSImage?
    private var suppressActions = false

    private lazy var mainFeatureToggle = makeCheckbox(title: "", action: #selector(mainFeatureToggled))
    private lazy var turboToggle = makeCheckbox(title: "", action: #selector(turboToggled))
    private lazy var launchAtLoginToggle = makeCheckbox(title: "", action: #selector(launchAtLoginToggled))
    private lazy var hideMenuBarIconToggle = makeCheckbox(title: "", action: #selector(hideMenuBarIconToggled))
    private lazy var hideDockIconToggle = makeCheckbox(title: "", action: #selector(hideDockIconToggled))
    private let titleLabel = NSTextField(labelWithString: "FinderWrap")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let languageLabel = NSTextField(labelWithString: "")
    private let footerEmailLabel = NSTextField(labelWithString: "")
    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private lazy var printStatsButton = makeButton(title: "", action: #selector(printStatsClicked))
    private lazy var quitButton = makeButton(title: "", action: #selector(quitClicked))
    private let iconView = NSImageView(frame: .zero)

    init(language: AppLanguage, iconProvider: @escaping () -> NSImage?) {
        self.language = language
        self.iconProvider = iconProvider
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text(.panelTitle, language)
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
        updateLanguage(language)
        resizeWindowToFitContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func updateState(
        mainFeatureEnabled: Bool,
        turboEnabled: Bool,
        launchAtLoginEnabled: Bool,
        hideMenuBarIcon: Bool,
        hideDockIcon: Bool
    ) {
        suppressActions = true
        mainFeatureToggle.state = mainFeatureEnabled ? .on : .off
        turboToggle.state = turboEnabled ? .on : .off
        launchAtLoginToggle.state = launchAtLoginEnabled ? .on : .off
        hideMenuBarIconToggle.state = hideMenuBarIcon ? .on : .off
        hideDockIconToggle.state = hideDockIcon ? .on : .off
        suppressActions = false
    }

    func updateIcon(_ image: NSImage?) {
        iconView.image = image
    }

    func updateLanguage(_ language: AppLanguage) {
        self.language = language
        applyLocalizedText()
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        titleLabel.font = .boldSystemFont(ofSize: 22)
        subtitleLabel.textColor = .secondaryLabelColor

        iconView.image = iconProvider()
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 26, weight: .semibold)
        iconView.contentTintColor = .labelColor

        let headerStack = NSStackView(views: [iconView, titleLabel])
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 10

        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)
        languagePopup.controlSize = .small
        let languageRow = NSStackView(views: [languageLabel, languagePopup])
        languageRow.orientation = .horizontal
        languageRow.alignment = .centerY
        languageRow.spacing = 8

        let togglesStack = NSStackView(views: [
            mainFeatureToggle,
            turboToggle,
            launchAtLoginToggle,
            hideMenuBarIconToggle,
            hideDockIconToggle,
        ])
        togglesStack.orientation = .vertical
        togglesStack.alignment = .leading
        togglesStack.spacing = 8

        let actionRow = NSStackView(views: [printStatsButton, quitButton])
        actionRow.orientation = .horizontal
        actionRow.spacing = 10
        actionRow.distribution = .fillEqually

        footerEmailLabel.font = .systemFont(ofSize: 11)
        footerEmailLabel.textColor = .secondaryLabelColor
        footerEmailLabel.alignment = .right

        let container = NSStackView(views: [headerStack, subtitleLabel, languageRow, togglesStack, actionRow, footerEmailLabel])
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 14
        container.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            footerEmailLabel.widthAnchor.constraint(equalTo: container.widthAnchor),
            languagePopup.widthAnchor.constraint(equalToConstant: 140),
            iconView.widthAnchor.constraint(equalToConstant: 30),
            iconView.heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    private func resizeWindowToFitContent() {
        guard let window, let contentView = window.contentView else { return }
        contentView.layoutSubtreeIfNeeded()

        let targetContentHeight = max(290, contentView.fittingSize.height)
        window.setContentSize(NSSize(width: 420, height: targetContentHeight))
    }

    private func makeCheckbox(title: String, action: Selector) -> NSButton {
        let checkbox = NSButton(checkboxWithTitle: title, target: self, action: action)
        checkbox.setButtonType(.switch)
        return checkbox
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    private func applyLocalizedText() {
        window?.title = L10n.text(.panelTitle, language)
        subtitleLabel.stringValue = L10n.text(.panelSubtitle, language)
        languageLabel.stringValue = L10n.text(.panelLanguage, language)
        mainFeatureToggle.title = L10n.text(.panelMainFeature, language)
        turboToggle.title = L10n.text(.panelTurbo, language)
        launchAtLoginToggle.title = L10n.text(.panelLaunchAtLogin, language)
        hideMenuBarIconToggle.title = L10n.text(.panelHideMenuIcon, language)
        hideDockIconToggle.title = L10n.text(.panelHideDesktopIcon, language)
        printStatsButton.title = L10n.text(.panelPrintStats, language)
        quitButton.title = L10n.text(.panelQuit, language)
        footerEmailLabel.stringValue = "\(L10n.text(.panelDeveloperPrefix, language)): songzihan473@gmail.com"

        suppressActions = true
        languagePopup.removeAllItems()
        languagePopup.addItems(withTitles: [
            L10n.text(.menuLanguageChinese, language),
            L10n.text(.menuLanguageEnglish, language),
        ])
        languagePopup.selectItem(at: language == .zhHans ? 0 : 1)
        suppressActions = false
    }

    @objc
    private func mainFeatureToggled() {
        guard !suppressActions else { return }
        onMainFeatureChanged?(mainFeatureToggle.state == .on)
    }

    @objc
    private func turboToggled() {
        guard !suppressActions else { return }
        onTurboChanged?(turboToggle.state == .on)
    }

    @objc
    private func launchAtLoginToggled() {
        guard !suppressActions else { return }
        onLaunchAtLoginChanged?(launchAtLoginToggle.state == .on)
    }

    @objc
    private func hideMenuBarIconToggled() {
        guard !suppressActions else { return }
        onHideMenuBarIconChanged?(hideMenuBarIconToggle.state == .on)
    }

    @objc
    private func hideDockIconToggled() {
        guard !suppressActions else { return }
        onHideDockIconChanged?(hideDockIconToggle.state == .on)
    }

    @objc
    private func languageChanged() {
        guard !suppressActions else { return }
        let newLanguage: AppLanguage = languagePopup.indexOfSelectedItem == 1 ? .en : .zhHans
        onLanguageChanged?(newLanguage)
    }

    @objc
    private func printStatsClicked() {
        onPrintStats?()
    }

    @objc
    private func quitClicked() {
        onQuit?()
    }
}

private final class AppPreferences {
    struct StartupState {
        let mainEnabled: Bool
        let turboEnabled: Bool
        let hideMenuBarIcon: Bool
        let hideDockIcon: Bool
        let language: AppLanguage
    }

    private let defaults = UserDefaults.standard
    private let initializedKey = "finderwrap.preferences.initialized"
    private let mainEnabledKey = "finderwrap.mainEnabled"
    private let turboEnabledKey = "finderwrap.arrowTurboEnabled"
    private let hideMenuBarIconKey = "finderwrap.hideMenuBarIcon"
    private let hideDockIconKey = "finderwrap.hideDockIcon"
    private let languageKey = "finderwrap.language"

    func loadOrInitializeDefaults() -> StartupState {
        if !defaults.bool(forKey: initializedKey) {
            defaults.set(true, forKey: initializedKey)
            defaults.set(true, forKey: mainEnabledKey)
            defaults.set(false, forKey: turboEnabledKey)
            defaults.set(false, forKey: hideMenuBarIconKey)
            defaults.set(true, forKey: hideDockIconKey)
            defaults.set(AppLanguage.zhHans.rawValue, forKey: languageKey)
        }

        if defaults.object(forKey: hideMenuBarIconKey) == nil {
            defaults.set(false, forKey: hideMenuBarIconKey)
        }
        if defaults.object(forKey: hideDockIconKey) == nil {
            defaults.set(true, forKey: hideDockIconKey)
        }
        if defaults.object(forKey: languageKey) == nil {
            defaults.set(AppLanguage.zhHans.rawValue, forKey: languageKey)
        }

        let languageRaw = defaults.string(forKey: languageKey) ?? AppLanguage.zhHans.rawValue
        let language = AppLanguage(rawValue: languageRaw) ?? .zhHans

        return StartupState(
            mainEnabled: defaults.bool(forKey: mainEnabledKey),
            turboEnabled: defaults.bool(forKey: turboEnabledKey),
            hideMenuBarIcon: defaults.bool(forKey: hideMenuBarIconKey),
            hideDockIcon: defaults.bool(forKey: hideDockIconKey),
            language: language
        )
    }

    func setMainEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: mainEnabledKey)
    }

    func setTurboEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: turboEnabledKey)
    }

    func setHideMenuBarIcon(_ hidden: Bool) {
        defaults.set(hidden, forKey: hideMenuBarIconKey)
    }

    func setHideDockIcon(_ hidden: Bool) {
        defaults.set(hidden, forKey: hideDockIconKey)
    }

    func setLanguage(_ language: AppLanguage) {
        defaults.set(language.rawValue, forKey: languageKey)
    }
}

private final class LaunchAtLoginManager {
    private let agentLabel = "com.finderwrap.navigator.autostart"

    var isEnabled: Bool {
        FileManager.default.fileExists(atPath: agentPlistURL.path)
    }

    func enable() throws {
        guard let executableURL = resolveExecutableURL() else {
            throw LaunchAtLoginError.executableNotFound
        }

        let launchAgentsDir = agentPlistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: launchAgentsDir,
            withIntermediateDirectories: true
        )

        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": [executableURL.path],
            "RunAtLoad": true,
            "KeepAlive": false,
            "LimitLoadToSessionType": ["Aqua"],
        ]

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: agentPlistURL, options: .atomic)

        try bootstrapAgentIfNeeded()
    }

    func disable() throws {
        if isLoadedInLaunchd {
            _ = try runLaunchctl(args: ["bootout", launchdServiceTarget])
        }

        guard isEnabled else { return }
        do {
            try FileManager.default.removeItem(at: agentPlistURL)
        } catch {
            throw LaunchAtLoginError.removeFailed
        }
    }

    private var agentPlistURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(agentLabel).plist", isDirectory: false)
    }

    private var launchdServiceTarget: String {
        "gui/\(getuid())/\(agentLabel)"
    }

    private var launchdDomainTarget: String {
        "gui/\(getuid())"
    }

    private var isLoadedInLaunchd: Bool {
        let result = runLaunchctlAllowFailure(args: ["print", launchdServiceTarget])
        return result.exitCode == 0
    }

    private func bootstrapAgentIfNeeded() throws {
        guard !isLoadedInLaunchd else { return }
        _ = try runLaunchctl(args: ["bootstrap", launchdDomainTarget, agentPlistURL.path])
    }

    private func resolveExecutableURL() -> URL? {
        if let bundleExecutable = Bundle.main.executableURL {
            let normalized = bundleExecutable.resolvingSymlinksInPath()
            if FileManager.default.isExecutableFile(atPath: normalized.path) {
                return normalized
            }
        }

        guard let argv0 = CommandLine.arguments.first else {
            return nil
        }
        let rawURL = URL(fileURLWithPath: argv0)
        let absoluteURL: URL
        if rawURL.path.hasPrefix("/") {
            absoluteURL = rawURL
        } else {
            let cwd = FileManager.default.currentDirectoryPath
            absoluteURL = URL(fileURLWithPath: cwd).appendingPathComponent(argv0)
        }
        let normalized = absoluteURL.resolvingSymlinksInPath()
        if FileManager.default.isExecutableFile(atPath: normalized.path) {
            return normalized
        }
        return nil
    }

    private func runLaunchctl(args: [String]) throws -> String {
        let result = runLaunchctlAllowFailure(args: args)
        guard result.exitCode == 0 else {
            throw LaunchAtLoginError.launchctlFailed(
                command: args.joined(separator: " "),
                output: result.output
            )
        }
        return result.output
    }

    private func runLaunchctlAllowFailure(args: [String]) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (1, error.localizedDescription)
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }
}

private enum LaunchAtLoginError: LocalizedError {
    case executableNotFound
    case removeFailed
    case launchctlFailed(command: String, output: String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "无法定位当前可执行文件，无法设置开机启动。"
        case .removeFailed:
            return "移除开机启动项失败，请检查权限。"
        case .launchctlFailed(let command, let output):
            let message = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if message.isEmpty {
                return "launchctl 执行失败: \(command)"
            }
            return "launchctl 执行失败: \(command)\n\(message)"
        }
    }
}

private final class SingleInstanceGuard {
    private var lockFD: Int32 = -1
    private let lockPath: String

    init() {
        let cachesDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("com.finderwrap.navigator", isDirectory: true)
        try? FileManager.default.createDirectory(at: cachesDirectory, withIntermediateDirectories: true)
        lockPath = cachesDirectory
            .appendingPathComponent("instance.lock", isDirectory: false)
            .path
    }

    func acquire() -> Bool {
        if lockFD != -1 {
            return true
        }

        let fd = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else {
            return false
        }

        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return false
        }

        if ftruncate(fd, 0) == 0 {
            let pidText = "\(getpid())\n"
            _ = pidText.withCString { pointer in
                write(fd, pointer, strlen(pointer))
            }
        }

        lockFD = fd
        return true
    }

    func release() {
        guard lockFD != -1 else {
            return
        }
        _ = flock(lockFD, LOCK_UN)
        close(lockFD)
        lockFD = -1
    }

    deinit {
        release()
    }
}
