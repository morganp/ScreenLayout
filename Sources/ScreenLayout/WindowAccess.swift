import AppKit
import ApplicationServices
import SpaceBridge

enum WindowAccess {
    static var trusted: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private static func value<T>(_ element: AXUIElement, _ key: String) -> T? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &raw) == .success else { return nil }
        return raw as? T
    }

    private static func point(_ element: AXUIElement, _ key: String) -> CGPoint? {
        guard let raw: AXValue = value(element, key) else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(raw, .cgPoint, &point) ? point : nil
    }

    private static func size(_ element: AXUIElement, _ key: String) -> CGSize? {
        guard let raw: AXValue = value(element, key) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(raw, .cgSize, &size) ? size : nil
    }

    private static func appElement(_ pid: pid_t) -> AXUIElement {
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 1.0)
        return root
    }

    private static func windows(for app: NSRunningApplication) -> [AXUIElement] {
        value(appElement(app.processIdentifier), kAXWindowsAttribute) ?? []
    }

    private static func match(_ placement: WindowPlacement, in candidates: [AXUIElement],
                              claimed: Set<UInt32>) -> AXUIElement? {
        let titled = candidates.first(where: {
            (value($0, kAXTitleAttribute) as String?) == placement.title &&
            !claimed.contains(SLWindowIDForAXElement($0))
        })
        let ordinal = candidates.indices.contains(placement.ordinal) ? candidates[placement.ordinal] : nil
        return titled ?? (ordinal.flatMap { claimed.contains(SLWindowIDForAXElement($0)) ? nil : $0 })
            ?? candidates.first(where: { !claimed.contains(SLWindowIDForAXElement($0)) })
    }

    private static func setSize(_ window: AXUIElement, _ size: CGSize) -> Bool {
        var size = size
        guard let sizeValue = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue) == .success
    }

    private static func setPosition(_ window: AXUIElement, _ origin: CGPoint) -> Bool {
        var origin = origin
        guard let positionValue = AXValueCreate(.cgPoint, &origin) else { return false }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue) == .success
    }

    // Position, size, position: the first move lets the target display clamp the origin, the size then
    // fits the new location and the last move corrects any shift the size change caused.
    private static func applyFrame(_ window: AXUIElement, _ frame: CGRect) -> Bool {
        let first = setPosition(window, frame.origin)
        let sized = setSize(window, frame.size)
        let last = setPosition(window, frame.origin)
        return first && sized && last
    }

    // Set by LayoutStore so placement mismatches reach the footer Event log.
    nonisolated(unsafe) static var diagnostics: ((String) -> Void)?
    nonisolated(unsafe) private static var reported: [UInt32: CGRect] = [:]

    // Call at the start of a restore so a repeated mismatch is logged again.
    static func resetDiagnostics() { reported = [:] }

    private static func describe(_ rect: CGRect) -> String {
        "(\(Int(rect.minX.rounded())), \(Int(rect.minY.rounded()))) \(Int(rect.width.rounded()))x\(Int(rect.height.rounded()))"
    }

    private static func differs(_ actual: CGRect, _ target: CGRect, size: Bool, tolerance: CGFloat) -> Bool {
        abs(actual.minX - target.minX) > tolerance || abs(actual.minY - target.minY) > tolerance
            || (size && (abs(actual.width - target.width) > tolerance || abs(actual.height - target.height) > tolerance))
    }

    // Logs once per window and target when the read-back frame is more than 2 points from the target.
    private static func report(_ window: AXUIElement, requested: CGRect, target: CGRect, actual: CGRect?,
                               display: DisplayInfo?, checkSize: Bool) {
        guard let actual, differs(actual, target, size: checkSize, tolerance: 2) else { return }
        let id = SLWindowIDForAXElement(window)
        if reported[id] == target { return }
        reported[id] = target
        var pid: pid_t = 0
        _ = AXUIElementGetPid(window, &pid)
        let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"
        let clamped = requested == target ? "" : ", clamped to \(describe(target))"
        diagnostics?("\(name) placement differs: requested \(describe(requested))\(clamped), actual \(describe(actual)), display \(display?.name ?? "unknown") usable \(display.map { describe($0.usableFrame) } ?? "unknown")")
    }

    // The target limited to the area macOS will accept (below the menu bar, clear of a visible Dock).
    // It never changes the saved rectangle.
    private static func clamped(_ frame: CGRect, to usable: CGRect?) -> CGRect {
        guard let usable, usable.width > 0, usable.height > 0 else { return frame }
        let width = min(frame.width, usable.width)
        let height = min(frame.height, usable.height)
        return CGRect(x: min(max(frame.minX, usable.minX), usable.maxX - width),
                      y: min(max(frame.minY, usable.minY), usable.maxY - height),
                      width: width, height: height)
    }

    // Moves the window inside `usable` when an enforced minimum size left it overhanging.
    private static func fit(_ window: AXUIElement, in usable: CGRect?) {
        guard let usable, let actual = frame(of: window) else { return }
        let x = min(max(actual.minX, usable.minX), max(usable.minX, usable.maxX - actual.width))
        let y = min(max(actual.minY, usable.minY), max(usable.minY, usable.maxY - actual.height))
        if abs(x - actual.minX) > 1 || abs(y - actual.minY) > 1 { _ = setPosition(window, CGPoint(x: x, y: y)) }
    }

    // The one way any path places a window: clamp to the display's usable area, set position, size,
    // position, read the frame back and retry once if it differs, then log a lasting mismatch.
    @discardableResult
    static func setFrame(_ window: AXUIElement, _ requested: CGRect, display: DisplayInfo?) -> Bool {
        let target = clamped(requested, to: display?.usableFrame)
        var ok = applyFrame(window, target)
        var actual = frame(of: window)
        if let current = actual, differs(current, target, size: true, tolerance: 1) {
            Thread.sleep(forTimeInterval: 0.05)
            ok = applyFrame(window, target)
            actual = frame(of: window)
        }
        report(window, requested: requested, target: target, actual: actual, display: display, checkSize: true)
        return ok
    }

    static func focusedWindow() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        if let focused: AXUIElement = value(system, kAXFocusedWindowAttribute),
           SLWindowIDForAXElement(focused) != 0 { return focused }
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return nil }
        return value(appElement(frontmost.processIdentifier), kAXFocusedWindowAttribute)
    }

    static func focusedWindowID() -> UInt32 {
        focusedWindow().map { SLWindowIDForAXElement($0) } ?? 0
    }

    // The point is in Core Graphics global coordinates (origin top left of the primary display).
    static func windowUnderCursor(at point: CGPoint) -> AXUIElement? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
              let element = hit else { return nil }
        AXUIElementSetMessagingTimeout(element, 1.0)
        if let window: AXUIElement = value(element, kAXWindowAttribute) { return window }
        return (value(element, kAXRoleAttribute) as String?) == kAXWindowRole ? element : nil
    }

    static func windowID(of window: AXUIElement) -> UInt32 { SLWindowIDForAXElement(window) }

    static func frame(of window: AXUIElement) -> CGRect? {
        guard let origin = point(window, kAXPositionAttribute), let extent = size(window, kAXSizeAttribute) else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    // Snap and undo placement; shares setFrame, then keeps the window inside the usable area when the
    // app enforced a larger minimum size.
    @discardableResult
    static func place(_ window: AXUIElement, at frame: CGRect, display: DisplayInfo? = nil) -> Bool {
        let ok = setFrame(window, frame, display: display)
        fit(window, in: display?.usableFrame)
        return ok
    }

    static func placement(for window: AXUIElement, displays: [DisplayInfo]) -> WindowPlacement? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success,
              let app = NSRunningApplication(processIdentifier: pid),
              let bundleID = app.bundleIdentifier, bundleID != Bundle.main.bundleIdentifier else { return nil }
        let ordinal = windows(for: app).firstIndex(where: { CFEqual($0, window) }) ?? 0
        return makePlacement(app: app, bundleID: bundleID, window: window, ordinal: ordinal, displays: displays)
    }

    // Reverse of restore matching: finds the placement the shared matcher would assign to this window.
    static func placementIndex(of window: AXUIElement, in placements: [WindowPlacement]) -> Int? {
        let target = SLWindowIDForAXElement(window)
        guard target != 0 else { return nil }
        var claimed: Set<UInt32> = []
        for (index, placement) in placements.enumerated() {
            let id = windowID(for: placement, claimed: claimed)
            if id == target { return index }
            if id != 0 { claimed.insert(id) }
        }
        return nil
    }

    private static func makePlacement(app: NSRunningApplication, bundleID: String, window: AXUIElement,
                                      ordinal: Int, displays: [DisplayInfo]) -> WindowPlacement? {
        guard let frame = Self.frame(of: window), frame.width > 10, frame.height > 10,
              let display = displays.max(by: { $0.frame.intersection(frame).area < $1.frame.intersection(frame).area }) else { return nil }
        let title: String = value(window, kAXTitleAttribute) ?? ""
        return WindowPlacement(bundleID: bundleID, appName: app.localizedName ?? bundleID,
                               title: title, ordinal: ordinal, displayID: display.id,
                               rect: UnitRect(frame, in: display.visibleFrame))
    }

    static func windowID(for placement: WindowPlacement, claimed: Set<UInt32> = []) -> UInt32 {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == placement.bundleID }) else { return 0 }
        return match(placement, in: windows(for: app), claimed: claimed).map(SLWindowIDForAXElement) ?? 0
    }

    static func setDrawerFrame(edge: DrawerEdge, expanded: Bool, display info: DisplayInfo,
                               restingFrame: CGRect, expandedRect: UnitRect,
                               windowID: UInt32, bundleID: String) -> Bool {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }),
              let window = windows(for: app).first(where: { SLWindowIDForAXElement($0) == windowID }) else { return false }
        let display = info.visibleFrame
        let usable = info.usableFrame
        if expanded {
            let ok = setFrame(window, expandedRect.frame(in: display), display: info)
            fit(window, in: usable)
            return ok
        }
        // Resting: a window with a minimum size larger than the strip is pushed off-screen so only
        // the strip shows, so only the position is verified.
        let frame = restingFrame
        _ = setPosition(window, frame.origin)
        guard setSize(window, frame.size) else { return false }
        let actualSize = self.size(window, kAXSizeAttribute) ?? frame.size
        let x = edge.isLeft ? display.minX - max(0, actualSize.width - frame.width)
            : (edge.isRight ? display.maxX - frame.width : frame.midX - actualSize.width / 2)
        let y = edge.isTop ? display.minY - max(0, actualSize.height - frame.height)
            : (edge.isBottom ? display.maxY - frame.height : frame.midY - actualSize.height / 2)
        var ok = setPosition(window, CGPoint(x: x, y: y))
        // macOS keeps a window below the menu bar, so that is where a top strip can rest.
        let expectedY = max(y, usable.minY)
        let expected = CGRect(x: x, y: expectedY, width: actualSize.width, height: actualSize.height)
        var actual = self.frame(of: window)
        if let current = actual, differs(current, expected, size: false, tolerance: 1) {
            Thread.sleep(forTimeInterval: 0.05)
            ok = applyFrame(window, CGRect(origin: CGPoint(x: x, y: y), size: actualSize))
            actual = self.frame(of: window)
        }
        report(window, requested: CGRect(origin: CGPoint(x: x, y: y), size: frame.size), target: expected,
               actual: actual, display: info, checkSize: false)
        return ok
    }

    static func capture(displays: [DisplayInfo]) -> [WindowPlacement] {
        guard trusted else { return [] }
        var result: [WindowPlacement] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier, bundleID != Bundle.main.bundleIdentifier else { continue }
            for (ordinal, window) in windows(for: app).enumerated() {
                if let placement = makePlacement(app: app, bundleID: bundleID, window: window,
                                                 ordinal: ordinal, displays: displays) {
                    result.append(placement)
                }
            }
        }
        return result
    }

    static func restore(_ placements: [WindowPlacement], displays: [DisplayInfo]) -> (moved: Int, skipped: Int) {
        guard trusted else { return (0, placements.count) }
        var moved = 0
        var skipped = 0
        var claimed: Set<UInt32> = []
        resetDiagnostics()
        for placement in placements {
            guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == placement.bundleID }),
                  let display = displays.first(where: { $0.id == placement.displayID }) else {
                skipped += 1
                continue
            }
            guard let window = match(placement, in: windows(for: app), claimed: claimed) else { skipped += 1; continue }
            claimed.insert(SLWindowIDForAXElement(window))
            if setFrame(window, placement.rect.frame(in: display.visibleFrame), display: display) { moved += 1 } else { skipped += 1 }
        }
        return (moved, skipped)
    }

    static func restoreAcrossSpaces(_ placements: [WindowPlacement], displays: [DisplayInfo],
                                    targetSpaces: [UUID: UInt64]) -> (moved: Int, skipped: Int, spaceFailed: Int) {
        guard trusted else { return (0, placements.count, 0) }
        var moved = 0
        var skipped = 0
        var spaceFailed = 0
        var usedWindowIDs: Set<UInt32> = []
        resetDiagnostics()
        for placement in placements {
            guard let slotID = placement.spaceID, let targetSpace = targetSpaces[slotID],
                  let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == placement.bundleID }),
                  let display = displays.first(where: { $0.id == placement.displayID }) else {
                skipped += 1
                continue
            }
            guard let window = match(placement, in: windows(for: app), claimed: usedWindowIDs) else { skipped += 1; continue }
            let windowID = SLWindowIDForAXElement(window)
            guard windowID != 0 else { skipped += 1; continue }
            usedWindowIDs.insert(windowID)
            if SLSpaceForWindow(windowID) != targetSpace {
                guard SLMoveWindowToSpace(windowID, targetSpace) else { spaceFailed += 1; continue }
                var verified = false
                for _ in 0..<10 {
                    if SLSpaceForWindow(windowID) == targetSpace { verified = true; break }
                    Thread.sleep(forTimeInterval: 0.1)
                }
                guard verified else { spaceFailed += 1; continue }
            }
            if setFrame(window, placement.rect.frame(in: display.visibleFrame), display: display) { moved += 1 } else { skipped += 1 }
        }
        return (moved, skipped, spaceFailed)
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
