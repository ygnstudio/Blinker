import Foundation

/// A named, self-contained set of per-app rules — a scenario preset such as
/// "工作" (aggressive quits) or "个人" (relaxed). Exactly one profile is
/// active at a time; switching swaps the whole rule table at once.
public struct RuleProfile: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    /// User-facing name, e.g. "工作" or "会议". Stored as typed.
    public var name: String
    /// The rules belonging to this profile.
    public var rules: [AppRule]

    public init(id: UUID = UUID(), name: String, rules: [AppRule] = []) {
        self.id = id
        self.name = name
        self.rules = rules
    }
}

/// The persisted archive format for `RuleStore`: every profile plus which
/// one is active. Encoded as a single `UserDefaults` blob so the two never
/// drift apart.
struct ProfileArchive: Codable, Equatable, Sendable {
    var profiles: [RuleProfile]
    var activeProfileID: UUID
}
