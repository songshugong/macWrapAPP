import AppKit
import ApplicationServices
import Darwin

final class FinderRightArrowWrapService {
    enum StartError: Error {
        case notTrusted
        case tapCreateFailed
    }

    var isRunning: Bool {
        serviceEnabled
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var serviceEnabled = false
    private var activationObservation: NSObjectProtocol?
    private var isHandlingWrap = false

    private let syntheticEventTag: Int64 = 0x46575250
    private let finderBundleID = "com.apple.finder"
    private let quickLookBundleIDs: Set<String> = [
        "com.apple.quicklook.ui.helper",
        "com.apple.QuickLookUIService"
    ]
    private let rightArrowKeyCode: CGKeyCode = 124
    private let leftArrowKeyCode: CGKeyCode = 123
    private let downArrowKeyCode: CGKeyCode = 125
    private let upArrowKeyCode: CGKeyCode = 126

    private struct GridItem {
        let element: AXUIElement
        let position: CGPoint
        let size: CGSize
    }

    private struct GridContext {
        let appElement: AXUIElement
        let container: AXUIElement
        let rows: [[GridItem]]
        let selectedRowIndex: Int
        let selectedColumnIndex: Int
    }

    private enum BoundaryAction {
        case passthrough
        case clamp
        case select(AXUIElement)
    }

    private enum ArrowHandlingOutcome {
        case passthrough(remainingSlots: Int)
        case clamp
        case wrapped
        case failed
    }

    private enum WrapDirection {
        case right
        case left
    }

    private struct GridIndex {
        let row: Int
        let column: Int
    }

    private struct GridCacheEntry {
        let appPID: pid_t
        let containerHash: CFHashCode
        let builtAt: CFAbsoluteTime
        let rows: [[GridItem]]
        let indexMap: [CFHashCode: GridIndex]
    }

    private struct DiagnosticsCounters {
        var totalArrowEvents = 0
        var wrapAttempts = 0
        var wrapSucceeded = 0
        var clampCount = 0
        var passthroughCount = 0
        var selectFailureCount = 0
        var optionBypassCount = 0
        var textEditBypassCount = 0
        var repeatBypassCount = 0
        var pathPolicyBypassCount = 0
        var timeoutBypassCount = 0
        var cacheHitCount = 0
        var cacheMissCount = 0
        var rightArrowTurboChecks = 0
        var leftArrowTurboChecks = 0
        var rightTurboSyntheticSteps = 0
        var leftTurboSyntheticSteps = 0
    }

    private struct ResourceSnapshot {
        let timestamp: CFAbsoluteTime
        let cpuTimeSeconds: Double
        let residentBytes: UInt64
    }

    private struct ResourceCounters {
        var sampleCount = 0
        var cpuDeltaSamples = 0
        var accumulatedCPUPercent = 0.0
        var peakCPUPercent = 0.0
        var peakResidentBytes: UInt64 = 0
        var lastResidentBytes: UInt64 = 0
    }

    private var gridCache: GridCacheEntry?
    private var gridCacheTTL: CFTimeInterval = 0.14
    private var lastArrowEventAt: CFAbsoluteTime = 0
    private var repeatTrackingKeyCode: CGKeyCode?
    private var nextRepeatBoundaryCheckAt: CFAbsoluteTime = 0
    private var rightArrowHoldStartAt: CFAbsoluteTime = 0
    private var nextRightArrowTurboStepAt: CFAbsoluteTime = 0
    private var isRightArrowTurboActive = false
    private var leftArrowHoldStartAt: CFAbsoluteTime = 0
    private var nextLeftArrowTurboStepAt: CFAbsoluteTime = 0
    private var isLeftArrowTurboActive = false
    private var rightArrowTurboModeEnabled = false

    // Path policy: customize these prefixes as needed.
    // If `wrapEnabledPathPrefixes` is empty, all paths are enabled by default
    // except those explicitly listed in `nativeOnlyPathPrefixes`.
    private let wrapEnabledPathPrefixes: [String] = []
    private let nativeOnlyPathPrefixes: [String] = []
    private var cachedFinderDirectoryPath: String?
    private var cachedFinderDirectoryFetchedAt: CFAbsoluteTime = 0
    private let finderDirectoryCacheTTL: CFTimeInterval = 0.45

    private var diagnostics = DiagnosticsCounters()
    private var resourceCounters = ResourceCounters()
    private var lastResourceSnapshot: ResourceSnapshot?
    private var resourceTimer: DispatchSourceTimer?
    private let resourceSampleInterval: CFTimeInterval = 2.0

    private let fallbackEnabled = false
    private let processingBudget: CFTimeInterval = 0.014
    private let repeatBoundaryCheckInterval: CFTimeInterval = 0.034
    private let rightArrowTurboActivationDelay: CFTimeInterval = 0.22
    private let rightArrowTurboRepeatInterval: CFTimeInterval = 0.010
    private let rightArrowTurboSyntheticStepInterval: CFTimeInterval = 0.018
    private let adaptiveIrregularRowWrapEnabled = false

    func isRightArrowTurboEnabled() -> Bool {
        rightArrowTurboModeEnabled
    }

    func setRightArrowTurboEnabled(_ enabled: Bool) {
        rightArrowTurboModeEnabled = enabled
        if !enabled {
            clearTurboState()
        }
    }

    func start() throws {
        guard !serviceEnabled else { return }

        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            throw StartError.notTrusted
        }

        activationObservation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _ = self?.refreshTapForFrontmostApp()
        }

        serviceEnabled = true
        let activated = refreshTapForFrontmostApp()
        if !activated {
            serviceEnabled = false
            if let activationObservation {
                NSWorkspace.shared.notificationCenter.removeObserver(activationObservation)
                self.activationObservation = nil
            }
            throw StartError.tapCreateFailed
        }

        resetDiagnosticsAndResources()
        startResourceSampling()
    }

    private func createEventTap() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else {
                return Unmanaged.passUnretained(event)
            }
            let service = Unmanaged<FinderRightArrowWrapService>
                .fromOpaque(refcon)
                .takeUnretainedValue()
            return service.handleEvent(proxy: proxy, type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        return true
    }

    private func refreshTapForFrontmostApp() -> Bool {
        guard serviceEnabled else { return true }

        if shouldObserveArrowKeysForFrontmostApp() {
            if eventTap == nil {
                return createEventTap()
            }
        } else {
            deactivateEventTap()
        }
        return true
    }

    func stop() {
        guard serviceEnabled else { return }
        serviceEnabled = false

        if let activationObservation {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObservation)
            self.activationObservation = nil
        }

        deactivateEventTap()
        stopResourceSampling()
        gridCache = nil
        lastArrowEventAt = 0
        repeatTrackingKeyCode = nil
        nextRepeatBoundaryCheckAt = 0
        clearTurboState()
        cachedFinderDirectoryPath = nil
        cachedFinderDirectoryFetchedAt = 0

        print(runtimeReport(reason: "stop"))
    }

    func runtimeReport(reason: String = "manual") -> String {
        captureResourceSample()

        let avgCPUPercent: Double
        if resourceCounters.cpuDeltaSamples > 0 {
            avgCPUPercent = resourceCounters.accumulatedCPUPercent / Double(resourceCounters.cpuDeltaSamples)
        } else {
            avgCPUPercent = 0
        }
        let peakResidentMB = Double(resourceCounters.peakResidentBytes) / (1024 * 1024)
        let lastResidentMB = Double(resourceCounters.lastResidentBytes) / (1024 * 1024)

        return """
        [FinderWrap] Runtime Report (\(reason))
        Counters:
          totalArrowEvents: \(diagnostics.totalArrowEvents)
          wrapAttempts: \(diagnostics.wrapAttempts)
          wrapSucceeded: \(diagnostics.wrapSucceeded)
          clampCount: \(diagnostics.clampCount)
          passthroughCount: \(diagnostics.passthroughCount)
          selectFailureCount: \(diagnostics.selectFailureCount)
          optionBypassCount: \(diagnostics.optionBypassCount)
          textEditBypassCount: \(diagnostics.textEditBypassCount)
          repeatBypassCount: \(diagnostics.repeatBypassCount)
          pathPolicyBypassCount: \(diagnostics.pathPolicyBypassCount)
          timeoutBypassCount: \(diagnostics.timeoutBypassCount)
          cacheHitCount: \(diagnostics.cacheHitCount)
          cacheMissCount: \(diagnostics.cacheMissCount)
          rightArrowTurboChecks: \(diagnostics.rightArrowTurboChecks)
          leftArrowTurboChecks: \(diagnostics.leftArrowTurboChecks)
          rightTurboSyntheticSteps: \(diagnostics.rightTurboSyntheticSteps)
          leftTurboSyntheticSteps: \(diagnostics.leftTurboSyntheticSteps)
        Resources:
          samples: \(resourceCounters.sampleCount)
          avgCPUPercent: \(String(format: "%.2f", avgCPUPercent))
          peakCPUPercent: \(String(format: "%.2f", resourceCounters.peakCPUPercent))
          lastResidentMB: \(String(format: "%.2f", lastResidentMB))
          peakResidentMB: \(String(format: "%.2f", peakResidentMB))
        PathPolicy:
          wrapEnabledPathPrefixes: \(wrapEnabledPathPrefixes)
          nativeOnlyPathPrefixes: \(nativeOnlyPathPrefixes)
          currentFinderDirectory: \(cachedFinderDirectoryPath ?? "unknown")
        Toggles:
          arrowTurboModeEnabled: \(rightArrowTurboModeEnabled)
        """
    }

    private func resetDiagnosticsAndResources() {
        diagnostics = DiagnosticsCounters()
        resourceCounters = ResourceCounters()
        lastResourceSnapshot = nil
    }

    private func startResourceSampling() {
        stopResourceSampling()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + resourceSampleInterval, repeating: resourceSampleInterval)
        timer.setEventHandler { [weak self] in
            self?.captureResourceSample()
        }
        timer.resume()
        resourceTimer = timer
        captureResourceSample()
    }

    private func stopResourceSampling() {
        resourceTimer?.cancel()
        resourceTimer = nil
    }

    private func deactivateEventTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CFMachPortInvalidate(tap)
        eventTap = nil
        runLoopSource = nil
    }

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == syntheticEventTag {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == rightArrowKeyCode || keyCode == leftArrowKeyCode else {
            return Unmanaged.passUnretained(event)
        }
        diagnostics.totalArrowEvents += 1

        let flags = event.flags
        if flags.contains(.maskAlternate) {
            diagnostics.optionBypassCount += 1
            diagnostics.passthroughCount += 1
            return Unmanaged.passUnretained(event)
        }

        let blockedFlags: CGEventFlags = [.maskCommand, .maskControl, .maskShift]
        guard flags.intersection(blockedFlags).isEmpty else {
            diagnostics.passthroughCount += 1
            return Unmanaged.passUnretained(event)
        }

        guard shouldObserveArrowKeysForFrontmostApp() else {
            diagnostics.passthroughCount += 1
            return Unmanaged.passUnretained(event)
        }

        let now = CFAbsoluteTimeGetCurrent()
        if !shouldHandleWrapForCurrentFinderPath(now: now) {
            diagnostics.pathPolicyBypassCount += 1
            diagnostics.passthroughCount += 1
            return Unmanaged.passUnretained(event)
        }

        if isFinderEditingText() {
            diagnostics.textEditBypassCount += 1
            diagnostics.passthroughCount += 1
            return Unmanaged.passUnretained(event)
        }

        updateDynamicCacheTTL(now: now)
        let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) == 1
        if shouldBypassBoundaryCheckForRepeat(
            keyCode: keyCode,
            isAutoRepeat: isAutoRepeat,
            now: now
        ) {
            diagnostics.repeatBypassCount += 1
            diagnostics.passthroughCount += 1
            return Unmanaged.passUnretained(event)
        }

        let deadline = now + processingBudget

        if keyCode == rightArrowKeyCode {
            let outcome = handleRightArrowAtBoundary(deadline: deadline, isAutoRepeat: isAutoRepeat)
            switch outcome {
            case .passthrough(let remainingSlots):
                maybePostRightArrowTurboStep(
                    now: now,
                    deadline: deadline,
                    isAutoRepeat: isAutoRepeat,
                    remainingRightSlots: remainingSlots
                )
                diagnostics.passthroughCount += 1
                return Unmanaged.passUnretained(event)
            case .clamp, .wrapped:
                return nil
            case .failed:
                diagnostics.passthroughCount += 1
                return Unmanaged.passUnretained(event)
            }
        }

        let outcome = handleLeftArrowAtBoundary(deadline: deadline, isAutoRepeat: isAutoRepeat)
        switch outcome {
        case .passthrough(let remainingSlots):
            maybePostLeftArrowTurboStep(
                now: now,
                deadline: deadline,
                isAutoRepeat: isAutoRepeat,
                remainingLeftSlots: remainingSlots
            )
            diagnostics.passthroughCount += 1
            return Unmanaged.passUnretained(event)
        case .clamp, .wrapped:
            return nil
        case .failed:
            diagnostics.passthroughCount += 1
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleRightArrowAtBoundary(
        deadline: CFAbsoluteTime,
        isAutoRepeat: Bool
    ) -> ArrowHandlingOutcome {
        _ = isAutoRepeat
        guard let context = buildGridContext(deadline: deadline) else {
            if CFAbsoluteTimeGetCurrent() > deadline {
                diagnostics.timeoutBypassCount += 1
            }
            return .failed
        }

        switch rightArrowAction(in: context) {
        case .passthrough:
            let row = context.rows[context.selectedRowIndex]
            let remainingRightSlots = max(0, row.count - context.selectedColumnIndex - 1)
            return .passthrough(remainingSlots: remainingRightSlots)
        case .clamp:
            diagnostics.clampCount += 1
            return .clamp
        case .select(let target):
            diagnostics.wrapAttempts += 1
            if selectTargetWithVerification(
                target,
                in: context.container,
                appElement: context.appElement,
                deadline: deadline
            ) {
                diagnostics.wrapSucceeded += 1
                return .wrapped
            }

            diagnostics.selectFailureCount += 1
            if fallbackEnabled {
                performRightArrowWrapFallback()
                return .wrapped
            }
            return .failed
        }
    }

    private func maybePostRightArrowTurboStep(
        now: CFAbsoluteTime,
        deadline: CFAbsoluteTime,
        isAutoRepeat: Bool,
        remainingRightSlots: Int
    ) {
        guard rightArrowTurboModeEnabled else { return }
        guard isAutoRepeat, isRightArrowTurboActive else { return }
        // Avoid edge races near row boundary; let native/fixed wrap logic take over.
        guard remainingRightSlots >= 2 else { return }
        guard now <= deadline else { return }
        guard now >= nextRightArrowTurboStepAt else { return }

        nextRightArrowTurboStepAt = now + rightArrowTurboSyntheticStepInterval
        postSyntheticArrow(rightArrowKeyCode)
        diagnostics.rightTurboSyntheticSteps += 1
    }

    private func maybePostLeftArrowTurboStep(
        now: CFAbsoluteTime,
        deadline: CFAbsoluteTime,
        isAutoRepeat: Bool,
        remainingLeftSlots: Int
    ) {
        guard rightArrowTurboModeEnabled else { return }
        guard isAutoRepeat, isLeftArrowTurboActive else { return }
        // Avoid edge races near row boundary; let native/fixed wrap logic take over.
        guard remainingLeftSlots >= 2 else { return }
        guard now <= deadline else { return }
        guard now >= nextLeftArrowTurboStepAt else { return }

        nextLeftArrowTurboStepAt = now + rightArrowTurboSyntheticStepInterval
        postSyntheticArrow(leftArrowKeyCode)
        diagnostics.leftTurboSyntheticSteps += 1
    }

    private func handleLeftArrowAtBoundary(
        deadline: CFAbsoluteTime,
        isAutoRepeat: Bool
    ) -> ArrowHandlingOutcome {
        _ = isAutoRepeat
        guard let context = buildGridContext(deadline: deadline) else {
            if CFAbsoluteTimeGetCurrent() > deadline {
                diagnostics.timeoutBypassCount += 1
            }
            return .failed
        }

        switch leftArrowAction(in: context) {
        case .passthrough:
            let remainingLeftSlots = max(0, context.selectedColumnIndex)
            return .passthrough(remainingSlots: remainingLeftSlots)
        case .clamp:
            diagnostics.clampCount += 1
            return .clamp
        case .select(let target):
            diagnostics.wrapAttempts += 1
            if selectTargetWithVerification(
                target,
                in: context.container,
                appElement: context.appElement,
                deadline: deadline
            ) {
                diagnostics.wrapSucceeded += 1
                return .wrapped
            }

            diagnostics.selectFailureCount += 1
            if fallbackEnabled {
                performLeftArrowWrapFallback()
                return .wrapped
            }
            return .failed
        }
    }

    private func performRightArrowWrapFallback() {
        guard !isHandlingWrap else {
            postSyntheticArrow(rightArrowKeyCode)
            return
        }

        isHandlingWrap = true
        defer { isHandlingWrap = false }

        let before = selectedItemToken()
        postSyntheticArrow(rightArrowKeyCode)
        usleep(30_000)

        guard let beforeToken = before else { return }
        guard let afterToken = selectedItemToken(), afterToken == beforeToken else {
            return
        }

        var currentToken = afterToken
        for _ in 0..<80 {
            postSyntheticArrow(leftArrowKeyCode)
            usleep(9_000)
            guard let latest = selectedItemToken() else { break }
            if latest == currentToken {
                break
            }
            currentToken = latest
        }

        postSyntheticArrow(downArrowKeyCode)
    }

    private func performLeftArrowWrapFallback() {
        guard !isHandlingWrap else {
            postSyntheticArrow(leftArrowKeyCode)
            return
        }

        isHandlingWrap = true
        defer { isHandlingWrap = false }

        let before = selectedItemToken()
        postSyntheticArrow(leftArrowKeyCode)
        usleep(30_000)

        guard let beforeToken = before else { return }
        guard let afterToken = selectedItemToken(), afterToken == beforeToken else {
            return
        }

        postSyntheticArrow(upArrowKeyCode)
        usleep(16_000)

        guard let upToken = selectedItemToken(), upToken != afterToken else {
            return
        }

        var currentToken = upToken
        for _ in 0..<80 {
            postSyntheticArrow(rightArrowKeyCode)
            usleep(9_000)
            guard let latest = selectedItemToken() else { break }
            if latest == currentToken {
                break
            }
            currentToken = latest
        }
    }

    private func buildGridContext(deadline: CFAbsoluteTime) -> GridContext? {
        guard CFAbsoluteTimeGetCurrent() <= deadline else { return nil }

        guard let app = finderRunningApplication() else { return nil }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let candidateRoots = selectionCandidateRoots(appElement: appElement)
        guard !candidateRoots.isEmpty else { return nil }

        for root in candidateRoots {
            guard CFAbsoluteTimeGetCurrent() <= deadline else { return nil }
            guard let context = buildGridContext(
                appElement: appElement,
                appPID: app.processIdentifier,
                root: root,
                deadline: deadline
            ) else {
                continue
            }
            return context
        }

        return nil
    }

    private func buildGridContext(
        appElement: AXUIElement,
        appPID: pid_t,
        root: AXUIElement,
        deadline: CFAbsoluteTime
    ) -> GridContext? {
        guard let (container, selectedElement) = findSelectionContainer(startingAt: root),
              isLikelyIconViewContainer(container) else {
            return nil
        }
        let containerHash = CFHash(container)

        let rows: [[GridItem]]
        let indexMap: [CFHashCode: GridIndex]
        var usedCache = false

        if let cache = validGridCache(appPID: appPID, containerHash: containerHash) {
            rows = cache.rows
            indexMap = cache.indexMap
            usedCache = true
            diagnostics.cacheHitCount += 1
        } else {
            diagnostics.cacheMissCount += 1
            guard CFAbsoluteTimeGetCurrent() <= deadline else { return nil }
            guard let built = buildRowsAndIndex(for: container) else { return nil }
            rows = built.rows
            indexMap = built.indexMap
            updateGridCache(
                appPID: appPID,
                containerHash: containerHash,
                rows: rows,
                indexMap: indexMap
            )
        }

        if let location = selectedLocation(of: selectedElement, in: rows, using: indexMap) {
            return GridContext(
                appElement: appElement,
                container: container,
                rows: rows,
                selectedRowIndex: location.row,
                selectedColumnIndex: location.column
            )
        }

        guard usedCache else {
            return nil
        }

        guard let rebuilt = buildRowsAndIndex(for: container),
              let rebuiltLocation = selectedLocation(
                  of: selectedElement,
                  in: rebuilt.rows,
                  using: rebuilt.indexMap
              ) else {
            return nil
        }

        updateGridCache(
            appPID: appPID,
            containerHash: containerHash,
            rows: rebuilt.rows,
            indexMap: rebuilt.indexMap
        )

        return GridContext(
            appElement: appElement,
            container: container,
            rows: rebuilt.rows,
            selectedRowIndex: rebuiltLocation.row,
            selectedColumnIndex: rebuiltLocation.column
        )
    }

    private func selectionCandidateRoots(appElement: AXUIElement) -> [AXUIElement] {
        var roots: [AXUIElement] = []
        var seen = Set<CFHashCode>()

        func appendUnique(_ element: AXUIElement?) {
            guard let element else { return }
            let hash = CFHash(element)
            guard !seen.contains(hash) else { return }
            seen.insert(hash)
            roots.append(element)
        }

        let focusedWindow = copyElementAttribute(of: appElement, key: kAXFocusedWindowAttribute as String)
        if let focusedWindow, isLikelyStandardFinderWindow(focusedWindow) {
            appendUnique(copyElementAttribute(of: appElement, key: kAXFocusedUIElementAttribute as String))
            appendUnique(focusedWindow)
        }

        // Quick Look keeps Finder frontmost but moves focus to its preview panel.
        // Search the ordinary Finder windows as a fallback so icon-view wrapping
        // still works while the preview window is open.
        if let windows = copyElementArrayAttribute(of: appElement, key: kAXWindowsAttribute as String) {
            for window in windows where isLikelyStandardFinderWindow(window) {
                appendUnique(window)
            }
        }

        return roots
    }

    private func isLikelyStandardFinderWindow(_ window: AXUIElement) -> Bool {
        let role = copyStringAttribute(of: window, key: kAXRoleAttribute as String) ?? ""
        guard role == "AXWindow" else { return false }

        let subrole = copyStringAttribute(of: window, key: kAXSubroleAttribute as String) ?? ""
        if subrole == "AXDesktop" || subrole == "AXDesktopWindow" {
            return false
        }

        let description = copyStringAttribute(of: window, key: kAXDescriptionAttribute as String) ?? ""
        let title = copyStringAttribute(of: window, key: kAXTitleAttribute as String) ?? ""
        let lowerIdentity = "\(subrole) \(description) \(title)".lowercased()
        if lowerIdentity.contains("quick look") || lowerIdentity.contains("quicklook") {
            return false
        }

        return true
    }

    private func isLikelyIconViewContainer(_ container: AXUIElement) -> Bool {
        let role = copyStringAttribute(of: container, key: kAXRoleAttribute as String) ?? ""
        if role == "AXOutline" || role == "AXBrowser" || role == "AXTable" {
            return false
        }

        let subrole = copyStringAttribute(of: container, key: kAXSubroleAttribute as String) ?? ""
        if subrole == "AXOutline" || subrole == "AXBrowser" || subrole == "AXTable" {
            return false
        }

        return true
    }

    private func isLikelyIconGrid(
        rows: [[GridItem]],
        rowAnchors: [CGFloat],
        items: [GridItem]
    ) -> Bool {
        guard rows.count >= 2 else {
            return false
        }

        let multiItemRows = rows.filter { $0.count >= 2 }.count
        guard multiItemRows >= 1 else {
            return false
        }

        let widths = items.map(\.size.width).sorted()
        let heights = items.map(\.size.height).sorted()
        guard let medianWidth = median(of: widths),
              let medianHeight = median(of: heights) else {
            return false
        }
        if medianWidth > 360 || medianHeight < 28 {
            return false
        }

        let aspect = medianWidth / max(medianHeight, 1)
        if aspect > 6 {
            return false
        }

        let sortedAnchors = rowAnchors.sorted()
        let rowGaps = zip(sortedAnchors, sortedAnchors.dropFirst()).map { abs($1 - $0) }
        if let medianGap = median(of: rowGaps), medianGap < 30 {
            return false
        }

        return true
    }

    private func buildRowsAndIndex(
        for container: AXUIElement
    ) -> (rows: [[GridItem]], indexMap: [CFHashCode: GridIndex])? {
        let allItems = collectGridItems(in: container)
        guard allItems.count >= 2 else { return nil }

        let rowTolerance = estimatedRowTolerance(from: allItems)
        let sorted = allItems.sorted {
            if abs($0.position.y - $1.position.y) > rowTolerance {
                return $0.position.y < $1.position.y
            }
            return $0.position.x < $1.position.x
        }

        var rows: [[GridItem]] = []
        var rowAnchors: [CGFloat] = []
        for item in sorted {
            if rows.isEmpty {
                rows.append([item])
                rowAnchors.append(item.position.y)
                continue
            }

            let rowIndex = rows.count - 1
            if abs(item.position.y - rowAnchors[rowIndex]) <= rowTolerance {
                rows[rowIndex].append(item)
                let count = CGFloat(rows[rowIndex].count)
                rowAnchors[rowIndex] = ((rowAnchors[rowIndex] * (count - 1)) + item.position.y) / count
            } else {
                rows.append([item])
                rowAnchors.append(item.position.y)
            }
        }

        rows = rows.map { row in row.sorted { $0.position.x < $1.position.x } }
        guard rows.contains(where: { $0.count >= 2 }) else {
            return nil
        }
        guard isLikelyIconGrid(rows: rows, rowAnchors: rowAnchors, items: allItems) else {
            return nil
        }

        let indexMap = buildIndexMap(for: rows)
        return (rows, indexMap)
    }

    private func selectedLocation(
        of selectedElement: AXUIElement,
        in rows: [[GridItem]],
        using indexMap: [CFHashCode: GridIndex]
    ) -> GridIndex? {
        let selectedHash = CFHash(selectedElement)
        if let index = indexMap[selectedHash],
           index.row < rows.count,
           index.column < rows[index.row].count,
           elementsEqual(rows[index.row][index.column].element, selectedElement) {
            return index
        }

        for (rowIndex, row) in rows.enumerated() {
            if let columnIndex = row.firstIndex(where: { elementsEqual($0.element, selectedElement) }) {
                return GridIndex(row: rowIndex, column: columnIndex)
            }
        }
        return nil
    }

    private func buildIndexMap(for rows: [[GridItem]]) -> [CFHashCode: GridIndex] {
        var indexMap: [CFHashCode: GridIndex] = [:]
        for (rowIndex, row) in rows.enumerated() {
            for (columnIndex, item) in row.enumerated() {
                let hash = CFHash(item.element)
                if indexMap[hash] == nil {
                    indexMap[hash] = GridIndex(row: rowIndex, column: columnIndex)
                }
            }
        }
        return indexMap
    }

    private func validGridCache(appPID: pid_t, containerHash: CFHashCode) -> GridCacheEntry? {
        guard let cache = gridCache else { return nil }
        guard cache.appPID == appPID, cache.containerHash == containerHash else {
            return nil
        }
        guard CFAbsoluteTimeGetCurrent() - cache.builtAt <= gridCacheTTL else {
            return nil
        }
        return cache
    }

    private func updateGridCache(
        appPID: pid_t,
        containerHash: CFHashCode,
        rows: [[GridItem]],
        indexMap: [CFHashCode: GridIndex]
    ) {
        gridCache = GridCacheEntry(
            appPID: appPID,
            containerHash: containerHash,
            builtAt: CFAbsoluteTimeGetCurrent(),
            rows: rows,
            indexMap: indexMap
        )
    }

    private func updateDynamicCacheTTL(now: CFAbsoluteTime) {
        if lastArrowEventAt <= 0 {
            gridCacheTTL = 0.14
            lastArrowEventAt = now
            return
        }

        let delta = now - lastArrowEventAt
        if delta <= 0.10 {
            gridCacheTTL = 0.28
        } else if delta <= 0.22 {
            gridCacheTTL = 0.18
        } else {
            gridCacheTTL = 0.12
        }
        lastArrowEventAt = now
    }

    private func shouldBypassBoundaryCheckForRepeat(
        keyCode: CGKeyCode,
        isAutoRepeat: Bool,
        now: CFAbsoluteTime
    ) -> Bool {
        guard isAutoRepeat else {
            repeatTrackingKeyCode = keyCode
            nextRepeatBoundaryCheckAt = 0
            clearTurboState()
            if rightArrowTurboModeEnabled {
                if keyCode == rightArrowKeyCode {
                    rightArrowHoldStartAt = now
                } else if keyCode == leftArrowKeyCode {
                    leftArrowHoldStartAt = now
                }
            }
            return false
        }

        if repeatTrackingKeyCode != keyCode {
            repeatTrackingKeyCode = keyCode
            clearTurboState()
            if rightArrowTurboModeEnabled {
                if keyCode == rightArrowKeyCode {
                    rightArrowHoldStartAt = now
                } else if keyCode == leftArrowKeyCode {
                    leftArrowHoldStartAt = now
                }
            }
            nextRepeatBoundaryCheckAt = now + effectiveRepeatBoundaryCheckInterval(for: keyCode, now: now)
            return false
        }

        let interval = effectiveRepeatBoundaryCheckInterval(for: keyCode, now: now)
        if now < nextRepeatBoundaryCheckAt {
            return true
        }

        nextRepeatBoundaryCheckAt = now + interval
        return false
    }

    private func effectiveRepeatBoundaryCheckInterval(for keyCode: CGKeyCode, now: CFAbsoluteTime) -> CFTimeInterval {
        guard keyCode == rightArrowKeyCode || keyCode == leftArrowKeyCode else {
            return repeatBoundaryCheckInterval
        }
        guard rightArrowTurboModeEnabled else {
            clearTurboState()
            return repeatBoundaryCheckInterval
        }

        if keyCode == rightArrowKeyCode {
            if rightArrowHoldStartAt <= 0 {
                rightArrowHoldStartAt = now
                isRightArrowTurboActive = false
                return repeatBoundaryCheckInterval
            }

            let holdDuration = now - rightArrowHoldStartAt
            let turboActive = holdDuration >= rightArrowTurboActivationDelay
            isRightArrowTurboActive = turboActive
            if turboActive {
                diagnostics.rightArrowTurboChecks += 1
                return rightArrowTurboRepeatInterval
            }
            return repeatBoundaryCheckInterval
        }

        if leftArrowHoldStartAt <= 0 {
            leftArrowHoldStartAt = now
            isLeftArrowTurboActive = false
            return repeatBoundaryCheckInterval
        }

        let holdDuration = now - leftArrowHoldStartAt
        let turboActive = holdDuration >= rightArrowTurboActivationDelay
        isLeftArrowTurboActive = turboActive
        if turboActive {
            diagnostics.leftArrowTurboChecks += 1
            return rightArrowTurboRepeatInterval
        }

        return repeatBoundaryCheckInterval
    }

    private func clearTurboState() {
        rightArrowHoldStartAt = 0
        nextRightArrowTurboStepAt = 0
        isRightArrowTurboActive = false
        leftArrowHoldStartAt = 0
        nextLeftArrowTurboStepAt = 0
        isLeftArrowTurboActive = false
    }

    private func isFinderEditingText() -> Bool {
        guard isFinderFrontmost(),
              let app = finderRunningApplication() else {
            return false
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let focusedElement = copyElementAttribute(
            of: appElement,
            key: kAXFocusedUIElementAttribute as String
        ) else {
            return false
        }

        let textRoles: Set<String> = [
            "AXTextField",
            "AXTextArea",
            "AXSearchField",
            "AXComboBox"
        ]
        let role = copyStringAttribute(of: focusedElement, key: kAXRoleAttribute as String) ?? ""
        if textRoles.contains(role) {
            return true
        }

        let isEditable = copyBoolAttribute(
            of: focusedElement,
            key: "AXEditable"
        ) ?? false
        let isFocused = copyBoolAttribute(
            of: focusedElement,
            key: kAXFocusedAttribute as String
        ) ?? false

        return isEditable && isFocused
    }

    private func shouldHandleWrapForCurrentFinderPath(now: CFAbsoluteTime) -> Bool {
        guard !wrapEnabledPathPrefixes.isEmpty || !nativeOnlyPathPrefixes.isEmpty else {
            return true
        }

        guard let path = currentFinderDirectoryPath(now: now) else {
            // Fail-open if path cannot be resolved.
            return true
        }

        let normalizedPath = normalizePath(path)
        let nativeOnlyMatches = nativeOnlyPathPrefixes.contains {
            normalizedPath.hasPrefix(normalizePath($0))
        }
        if nativeOnlyMatches {
            return false
        }

        if wrapEnabledPathPrefixes.isEmpty {
            return true
        }

        return wrapEnabledPathPrefixes.contains {
            normalizedPath.hasPrefix(normalizePath($0))
        }
    }

    private func currentFinderDirectoryPath(now: CFAbsoluteTime) -> String? {
        if now - cachedFinderDirectoryFetchedAt <= finderDirectoryCacheTTL {
            return cachedFinderDirectoryPath
        }

        let script = """
        tell application "Finder"
            if (count of Finder windows) is 0 then return ""
            try
                return POSIX path of (target of front window as alias)
            on error
                return ""
            end try
        end tell
        """

        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        let result = appleScript?.executeAndReturnError(&error)
        if error != nil {
            cachedFinderDirectoryPath = nil
            cachedFinderDirectoryFetchedAt = now
            return nil
        }

        let path = result?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        cachedFinderDirectoryPath = path.isEmpty ? nil : normalizePath(path)
        cachedFinderDirectoryFetchedAt = now
        return cachedFinderDirectoryPath
    }

    private func normalizePath(_ path: String) -> String {
        let standardized = (path as NSString).standardizingPath
        if standardized.hasSuffix("/") {
            return String(standardized.dropLast())
        }
        return standardized
    }

    private func captureResourceSample() {
        guard let snapshot = currentResourceSnapshot() else { return }

        resourceCounters.sampleCount += 1
        resourceCounters.lastResidentBytes = snapshot.residentBytes
        resourceCounters.peakResidentBytes = max(resourceCounters.peakResidentBytes, snapshot.residentBytes)

        if let previous = lastResourceSnapshot {
            let wallDelta = snapshot.timestamp - previous.timestamp
            let cpuDelta = snapshot.cpuTimeSeconds - previous.cpuTimeSeconds
            if wallDelta > 0, cpuDelta >= 0 {
                let cpuPercent = (cpuDelta / wallDelta) * 100.0
                resourceCounters.cpuDeltaSamples += 1
                resourceCounters.accumulatedCPUPercent += cpuPercent
                resourceCounters.peakCPUPercent = max(resourceCounters.peakCPUPercent, cpuPercent)
            }
        }

        lastResourceSnapshot = snapshot
    }

    private func currentResourceSnapshot() -> ResourceSnapshot? {
        var basicInfo = task_basic_info_data_t()
        var basicCount = mach_msg_type_number_t(MemoryLayout<task_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
        let basicKernResult: kern_return_t = withUnsafeMutablePointer(to: &basicInfo) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(basicCount)) { reboundPointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_BASIC_INFO),
                    reboundPointer,
                    &basicCount
                )
            }
        }
        guard basicKernResult == KERN_SUCCESS else {
            return nil
        }

        var timesInfo = task_thread_times_info_data_t()
        var timesCount = mach_msg_type_number_t(
            MemoryLayout<task_thread_times_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let timesKernResult: kern_return_t = withUnsafeMutablePointer(to: &timesInfo) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(timesCount)) { reboundPointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_THREAD_TIMES_INFO),
                    reboundPointer,
                    &timesCount
                )
            }
        }
        guard timesKernResult == KERN_SUCCESS else {
            return nil
        }

        let userSeconds = Double(timesInfo.user_time.seconds) + (Double(timesInfo.user_time.microseconds) / 1_000_000.0)
        let systemSeconds = Double(timesInfo.system_time.seconds) + (Double(timesInfo.system_time.microseconds) / 1_000_000.0)
        return ResourceSnapshot(
            timestamp: CFAbsoluteTimeGetCurrent(),
            cpuTimeSeconds: userSeconds + systemSeconds,
            residentBytes: UInt64(basicInfo.resident_size)
        )
    }

    private func rightArrowAction(in context: GridContext) -> BoundaryAction {
        let row = context.rows[context.selectedRowIndex]
        let current = row[context.selectedColumnIndex]
        let hasRightNeighbor = row.contains { $0.position.x > current.position.x + 1 }
        guard !hasRightNeighbor else {
            return .passthrough
        }

        let nextRowIndex = context.selectedRowIndex + 1
        guard nextRowIndex < context.rows.count else {
            return .clamp
        }

        let nextRow = context.rows[nextRowIndex]
        guard let target = wrapTarget(
            for: .right,
            currentItem: current,
            currentRow: row,
            targetRow: nextRow
        ) else {
            return .clamp
        }
        return .select(target.element)
    }

    private func leftArrowAction(in context: GridContext) -> BoundaryAction {
        let row = context.rows[context.selectedRowIndex]
        let current = row[context.selectedColumnIndex]
        let hasLeftNeighbor = row.contains { $0.position.x < current.position.x - 1 }
        guard !hasLeftNeighbor else {
            return .passthrough
        }

        let previousRowIndex = context.selectedRowIndex - 1
        guard previousRowIndex >= 0 else {
            return .clamp
        }

        let previousRow = context.rows[previousRowIndex]
        guard let target = wrapTarget(
            for: .left,
            currentItem: current,
            currentRow: row,
            targetRow: previousRow
        ) else {
            return .clamp
        }
        return .select(target.element)
    }

    private func wrapTarget(
        for direction: WrapDirection,
        currentItem: GridItem,
        currentRow: [GridItem],
        targetRow: [GridItem]
    ) -> GridItem? {
        guard !targetRow.isEmpty else { return nil }
        let rowCountDelta = abs(currentRow.count - targetRow.count)

        if adaptiveIrregularRowWrapEnabled && rowCountDelta >= 2 {
            let currentCenterX = currentItem.position.x + (currentItem.size.width * 0.5)
            return targetRow.min { lhs, rhs in
                let lhsCenter = lhs.position.x + (lhs.size.width * 0.5)
                let rhsCenter = rhs.position.x + (rhs.size.width * 0.5)
                let lhsDistance = abs(lhsCenter - currentCenterX)
                let rhsDistance = abs(rhsCenter - currentCenterX)
                if lhsDistance == rhsDistance {
                    return lhs.position.x < rhs.position.x
                }
                return lhsDistance < rhsDistance
            }
        }

        switch direction {
        case .right:
            return targetRow.min(by: { $0.position.x < $1.position.x })
        case .left:
            return targetRow.max(by: { $0.position.x < $1.position.x })
        }
    }

    private func selectTargetWithVerification(
        _ target: AXUIElement,
        in container: AXUIElement,
        appElement: AXUIElement,
        deadline: CFAbsoluteTime
    ) -> Bool {
        if selectSingleItem(target, in: container, appElement: appElement) {
            if verifySelection(target: target, appElement: appElement) {
                return true
            }
        } else {
            return false
        }

        guard CFAbsoluteTimeGetCurrent() <= deadline else {
            return false
        }

        usleep(2_500)

        guard selectSingleItem(target, in: container, appElement: appElement) else {
            return false
        }
        return verifySelection(target: target, appElement: appElement)
    }

    private func verifySelection(target: AXUIElement, appElement: AXUIElement) -> Bool {
        if copyBoolAttribute(of: target, key: kAXSelectedAttribute as String) == true {
            return true
        }

        guard let focused = copyElementAttribute(of: appElement, key: kAXFocusedUIElementAttribute as String),
              let selected = findSelectedElement(startingAt: focused) else {
            return false
        }
        return elementsEqual(selected, target)
    }

    private func selectSingleItem(
        _ target: AXUIElement,
        in container: AXUIElement,
        appElement: AXUIElement
    ) -> Bool {
        _ = appElement
        let singleSelection = [target] as CFArray
        let result = AXUIElementSetAttributeValue(
            container,
            kAXSelectedChildrenAttribute as CFString,
            singleSelection
        )
        if result == .success {
            return true
        }

        let fallbackResult = AXUIElementSetAttributeValue(
            target,
            kAXSelectedAttribute as CFString,
            kCFBooleanTrue
        )
        if fallbackResult == .success {
            return true
        }

        return false
    }

    private func findSelectionContainer(startingAt root: AXUIElement) -> (AXUIElement, AXUIElement)? {
        if let selected = firstSelectedChild(in: root) {
            return (root, selected)
        }

        var queue: [AXUIElement] = [root]
        var visited = Set<CFHashCode>()
        let maxVisited = 300

        while !queue.isEmpty && visited.count < maxVisited {
            let current = queue.removeFirst()
            let hash = CFHash(current)
            if visited.contains(hash) {
                continue
            }
            visited.insert(hash)

            if let selected = firstSelectedChild(in: current) {
                return (current, selected)
            }

            if let children = copyElementArrayAttribute(of: current, key: kAXChildrenAttribute as String) {
                queue.append(contentsOf: children)
            }
        }

        return nil
    }

    private func collectGridItems(in container: AXUIElement) -> [GridItem] {
        var queue: [AXUIElement] = [container]
        var visited = Set<CFHashCode>()
        var results: [GridItem] = []
        let maxVisited = 600

        while !queue.isEmpty && visited.count < maxVisited {
            let current = queue.removeFirst()
            let hash = CFHash(current)
            if visited.contains(hash) {
                continue
            }
            visited.insert(hash)

            if let item = gridItem(from: current) {
                results.append(item)
            }

            if let children = copyElementArrayAttribute(of: current, key: kAXChildrenAttribute as String) {
                queue.append(contentsOf: children)
            }
            if let rows = copyElementArrayAttribute(of: current, key: kAXRowsAttribute as String) {
                queue.append(contentsOf: rows)
            }
        }

        return results
    }

    private func gridItem(from element: AXUIElement) -> GridItem? {
        guard let position = copyPointAttribute(of: element, key: kAXPositionAttribute as String),
              let size = copySizeAttribute(of: element, key: kAXSizeAttribute as String) else {
            return nil
        }
        guard size.width >= 20, size.height >= 20 else { return nil }
        guard copyBoolAttribute(of: element, key: kAXSelectedAttribute as String) != nil else {
            return nil
        }

        let hasIdentity =
            copyStringAttribute(of: element, key: kAXTitleAttribute as String) != nil ||
            copyStringAttribute(of: element, key: kAXValueAttribute as String) != nil ||
            copyStringAttribute(of: element, key: kAXDescriptionAttribute as String) != nil ||
            copyStringAttribute(of: element, key: kAXIdentifierAttribute as String) != nil
        guard hasIdentity else { return nil }

        return GridItem(element: element, position: position, size: size)
    }

    private func estimatedRowTolerance(from items: [GridItem]) -> CGFloat {
        let heights = items.map(\.size.height).sorted()
        guard !heights.isEmpty else { return 18 }
        let median = heights[heights.count / 2]
        return max(12, median * 0.55)
    }

    private func median(of sortedValues: [CGFloat]) -> CGFloat? {
        guard !sortedValues.isEmpty else { return nil }
        return sortedValues[sortedValues.count / 2]
    }

    private func elementsEqual(_ lhs: AXUIElement, _ rhs: AXUIElement) -> Bool {
        CFEqual(lhs, rhs)
    }

    private func isFinderFrontmost() -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == finderBundleID
    }

    private func shouldObserveArrowKeysForFrontmostApp() -> Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return bundleID == finderBundleID || isQuickLookBundleID(bundleID)
    }

    private func isQuickLookBundleID(_ bundleID: String) -> Bool {
        if quickLookBundleIDs.contains(bundleID) {
            return true
        }
        return bundleID.lowercased().contains("quicklook")
    }

    private func finderRunningApplication() -> NSRunningApplication? {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier == finderBundleID {
            return frontmost
        }
        return NSRunningApplication.runningApplications(withBundleIdentifier: finderBundleID).first
    }

    private func selectedItemToken() -> String? {
        guard let app = finderRunningApplication() else { return nil }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let focusedElement = copyElementAttribute(
            of: appElement,
            key: kAXFocusedUIElementAttribute as String
        ) else {
            return nil
        }

        guard let selected = findSelectedElement(startingAt: focusedElement) else {
            return nil
        }

        return token(for: selected)
    }

    private func findSelectedElement(startingAt root: AXUIElement) -> AXUIElement? {
        if let selected = firstSelectedChild(in: root) {
            return selected
        }

        var queue: [AXUIElement] = [root]
        var visited = Set<CFHashCode>()
        let maxVisited = 300

        while !queue.isEmpty && visited.count < maxVisited {
            let current = queue.removeFirst()
            let hash = CFHash(current)
            if visited.contains(hash) { continue }
            visited.insert(hash)

            if let selected = firstSelectedChild(in: current) {
                return selected
            }

            if let children = copyElementArrayAttribute(of: current, key: kAXChildrenAttribute as String) {
                queue.append(contentsOf: children)
            }
        }

        return nil
    }

    private func firstSelectedChild(in element: AXUIElement) -> AXUIElement? {
        let candidateKeys = [
            kAXSelectedChildrenAttribute as String,
            kAXSelectedRowsAttribute as String,
            kAXSelectedCellsAttribute as String
        ]

        for key in candidateKeys {
            if let selected = copyElementArrayAttribute(of: element, key: key), !selected.isEmpty {
                return selected[0]
            }
        }
        return nil
    }

    private func token(for element: AXUIElement) -> String? {
        var parts: [String] = []

        if let identifier = copyStringAttribute(of: element, key: kAXIdentifierAttribute as String), !identifier.isEmpty {
            parts.append("id=\(identifier)")
        }
        if let title = copyStringAttribute(of: element, key: kAXTitleAttribute as String), !title.isEmpty {
            parts.append("title=\(title)")
        }
        if let value = copyStringAttribute(of: element, key: kAXValueAttribute as String), !value.isEmpty {
            parts.append("value=\(value)")
        }
        if let description = copyStringAttribute(of: element, key: kAXDescriptionAttribute as String), !description.isEmpty {
            parts.append("desc=\(description)")
        }

        if let point = copyPointAttribute(of: element, key: kAXPositionAttribute as String) {
            parts.append(String(format: "pos=%.1f,%.1f", point.x, point.y))
        }

        return parts.isEmpty ? nil : parts.joined(separator: "|")
    }

    private func postSyntheticArrow(_ keyCode: CGKeyCode) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        source.localEventsSuppressionInterval = 0

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }

        keyDown.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
        keyUp.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }

    private func copyElementAttribute(of element: AXUIElement, key: String) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        guard result == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func copyElementArrayAttribute(of element: AXUIElement, key: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        guard result == .success else { return nil }
        return value as? [AXUIElement]
    }

    private func copyStringAttribute(of element: AXUIElement, key: String) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    private func copyPointAttribute(of element: AXUIElement, key: String) -> CGPoint? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        guard result == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func copySizeAttribute(of element: AXUIElement, key: String) -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        guard result == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }

    private func copyBoolAttribute(of element: AXUIElement, key: String) -> Bool? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        guard result == .success, let number = value as? NSNumber else { return nil }
        return number.boolValue
    }
}
