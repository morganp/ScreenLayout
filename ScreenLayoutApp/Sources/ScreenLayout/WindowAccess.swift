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

    private static func windows(for app: NSRunningApplication) -> [AXUIElement] {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        return value(root, kAXWindowsAttribute) ?? []
    }

    static func capture(displays: [DisplayInfo]) -> [WindowPlacement] {
        guard trusted else { return [] }
        var result: [WindowPlacement] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier, bundleID != Bundle.main.bundleIdentifier else { continue }
            for (ordinal, window) in windows(for: app).enumerated() {
                guard let origin = point(window, kAXPositionAttribute),
                      let extent = size(window, kAXSizeAttribute),
                      extent.width > 10, extent.height > 10 else { continue }
                let frame = CGRect(origin: origin, size: extent)
                guard let display = displays.max(by: { $0.frame.intersection(frame).area < $1.frame.intersection(frame).area }) else { continue }
                let title: String = value(window, kAXTitleAttribute) ?? ""
                result.append(WindowPlacement(bundleID: bundleID, appName: app.localizedName ?? bundleID,
                                              title: title, ordinal: ordinal, displayID: display.id,
                                              rect: UnitRect(frame, in: display.visibleFrame)))
            }
        }
        return result
    }

    static func restore(_ placements: [WindowPlacement], displays: [DisplayInfo]) -> (moved: Int, skipped: Int) {
        guard trusted else { return (0, placements.count) }
        var moved = 0
        var skipped = 0
        for placement in placements {
            guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == placement.bundleID }),
                  let display = displays.first(where: { $0.id == placement.displayID }) else {
                skipped += 1
                continue
            }
            let candidates = windows(for: app)
            let titled = candidates.first(where: { (value($0, kAXTitleAttribute) as String?) == placement.title })
            let window = titled ?? (candidates.indices.contains(placement.ordinal) ? candidates[placement.ordinal] : nil)
            guard let window else { skipped += 1; continue }
            let frame = placement.rect.frame(in: display.visibleFrame)
            var size = frame.size
            var origin = frame.origin
            guard let sizeValue = AXValueCreate(.cgSize, &size),
                  let positionValue = AXValueCreate(.cgPoint, &origin) else { skipped += 1; continue }
            let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
            let positionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
            if sizeResult == .success && positionResult == .success { moved += 1 } else { skipped += 1 }
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
            let candidates = windows(for: app)
            let titled = candidates.first(where: {
                (value($0, kAXTitleAttribute) as String?) == placement.title &&
                !usedWindowIDs.contains(SLWindowIDForAXElement($0))
            })
            let ordinal = candidates.indices.contains(placement.ordinal) ? candidates[placement.ordinal] : nil
            let window = titled ?? (ordinal.flatMap { usedWindowIDs.contains(SLWindowIDForAXElement($0)) ? nil : $0 })
                ?? candidates.first(where: { !usedWindowIDs.contains(SLWindowIDForAXElement($0)) })
            guard let window else { skipped += 1; continue }
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
            let frame = placement.rect.frame(in: display.visibleFrame)
            var size = frame.size
            var origin = frame.origin
            guard let sizeValue = AXValueCreate(.cgSize, &size),
                  let positionValue = AXValueCreate(.cgPoint, &origin) else { skipped += 1; continue }
            let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
            let positionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
            if sizeResult == .success && positionResult == .success { moved += 1 } else { skipped += 1 }
        }
        return (moved, skipped, spaceFailed)
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
