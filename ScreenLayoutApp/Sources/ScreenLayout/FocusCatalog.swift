import Foundation

enum FocusCatalog {
    static func load() -> (names: [String], error: String?) {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB/ModeConfigurations.json")
        guard let data = try? Data(contentsOf: url) else {
            return ([], "Could not read \(url.path)")
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["data"] as? [[String: Any]],
              let modes = entries.first?["modeConfigurations"] as? [String: [String: Any]] else {
            return ([], "Could not parse local Focus settings")
        }
        let names = Array(Set(modes.values.compactMap { entry -> String? in
            guard let mode = entry["mode"] as? [String: Any],
                  (mode["visibility"] as? Int) == 0,
                  let name = mode["name"] as? String else { return nil }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        })).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return (names, nil)
    }
}
