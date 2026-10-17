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

    private static func setFrame(_ window: AXUIElement, _ frame: CGRect) -> Bool {
        let sized = setSize(window, frame.size)
        let positioned = setPosition(window, frame.origin)
        return sized && positioned
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

    // Moves then sizes, which suits snapping across displays, then keeps the result inside bounds
    // when the app enforced a larger minimum size.
    @discardableResult
    static func place(_ window: AXUIElement, at frame: CGRect, within bounds: CGRect? = nil) -> Bool {
        let positioned = setPosition(window, frame.origin)
        let sized = setSize(window, frame.size)
        guard let bounds, let actual = self.frame(of: window) else { return positioned && sized }
        let x = min(max(actual.minX, bounds.minX), max(bounds.minX, bounds.maxX - actual.width))
        let y = min(max(actual.minY, bounds.minY), max(bounds.minY, bounds.maxY - actual.height))
        if abs(x - actual.minX) > 1 || abs(y - actual.minY) > 1 { _ = setPosition(window, CGPoint(x: x, y: y)) }
        return positioned && sized
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

    static func setDrawerFrame(edge: DrawerEdge, expanded: Bool, display: CGRect,
                               restingFrame: CGRect, expandedRect: UnitRect,
                               windowID: UInt32, bundleID: String) -> Bool {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }),
              let window = windows(for: app).first(where: { SLWindowIDForAXElement($0) == windowID }) else { return false }
        let frame = expanded ? expandedRect.frame(in: display) : restingFrame
        guard setSize(window, frame.size) else { return false }
        let actualSize = self.size(window, kAXSizeAttribute) ?? frame.size
        let x: CGFloat
        if expanded {
            x = min(display.maxX - actualSize.width, max(display.minX, frame.minX))
        } else {
            x = edge.isLeft ? display.minX - max(0, actualSize.width - frame.width)
                : (edge.isRight ? display.maxX - frame.width : frame.midX - actualSize.width / 2)
        }
        let y: CGFloat
        if expanded {
            y = min(display.maxY - actualSize.height, max(display.minY, frame.minY))
        } else {
            y = edge.isTop ? display.minY - max(0, actualSize.height - frame.height)
                : (edge.isBottom ? display.maxY - frame.height : frame.midY - actualSize.height / 2)
        }
        return setPosition(window, CGPoint(x: x, y: y))
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
        for placement in placements {
            guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == placement.bundleID }),
                  let display = displays.first(where: { $0.id == placement.displayID }) else {
                skipped += 1
                continue
            }
            guard let window = match(placement, in: windows(for: app), claimed: claimed) else { skipped += 1; continue }
            claimed.insert(SLWindowIDForAXElement(window))
            if setFrame(window, placement.rect.frame(in: display.visibleFrame)) { moved += 1 } else { skipped += 1 }
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
            if setFrame(window, placement.rect.frame(in: display.visibleFrame)) { moved += 1 } else { skipped += 1 }
        }
        return (moved, skipped, spaceFailed)
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
