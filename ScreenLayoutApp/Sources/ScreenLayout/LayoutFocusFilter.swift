import AppIntents

struct LayoutFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Choose ScreenLayout profile"
    static let description: LocalizedStringResource? = "Use a saved window layout profile while this Focus is active."

    @Parameter(title: "Layout profile")
    var profile: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "ScreenLayout: \(profile ?? "Default")")
    }

    func perform() async throws -> some IntentResult {
        return .result()
    }
}
