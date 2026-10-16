import AppKit
import CoreFoundation
import Darwin

struct SpaceInfo: Identifiable, Hashable {
    let id: UInt64
    let type: Int
    let order: Int

    var isDesktop: Bool { type == 0 }
}

struct DisplaySpaces: Hashable {
    let displayID: String
    let spaces: [SpaceInfo]
    let currentID: UInt64?

    var desktopCount: Int { spaces.filter(\.isDesktop).count }
}

enum SpaceInventory {
    static func current() -> [DisplaySpaces]? {
        guard let framework = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
              let connectionSymbol = dlsym(framework, "SLSMainConnectionID"),
              let spacesSymbol = dlsym(framework, "SLSCopyManagedDisplaySpaces") else { return nil }
        defer { dlclose(framework) }
        let connection = unsafeBitCast(connectionSymbol, to: (@convention(c) () -> Int32).self)()
        let copySpaces = unsafeBitCast(spacesSymbol,
                                       to: (@convention(c) (Int32) -> UnsafeMutableRawPointer?).self)
        guard let pointer = copySpaces(connection) else { return nil }
        let displayArray = Unmanaged<CFArray>.fromOpaque(pointer).takeRetainedValue()
        var result: [DisplaySpaces] = []
        for index in 0..<CFArrayGetCount(displayArray) {
            guard let raw = CFArrayGetValueAtIndex(displayArray, index) else { continue }
            let dictionary = Unmanaged<CFDictionary>.fromOpaque(raw).takeUnretainedValue() as NSDictionary
            guard let displayID = dictionary["Display Identifier"] as? String,
                  let entries = dictionary["Spaces"] as? [NSDictionary] else { continue }
            let spaces = entries.enumerated().compactMap { order, entry -> SpaceInfo? in
                guard let id = entry["id64"] as? NSNumber,
                      let type = entry["type"] as? NSNumber else { return nil }
                return SpaceInfo(id: id.uint64Value, type: type.intValue, order: order + 1)
            }
            let current = dictionary["Current Space"] as? NSDictionary
            let currentID = (current?["id64"] as? NSNumber)?.uint64Value
            result.append(DisplaySpaces(displayID: displayID, spaces: spaces, currentID: currentID))
        }
        return result.isEmpty ? nil : result
    }
}
