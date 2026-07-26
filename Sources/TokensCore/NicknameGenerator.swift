import Foundation

public enum NicknameGenerator {
    private static let adjectives = [
        "amber", "azure", "cobalt", "coral", "crimson", "dusk", "ember", "frost",
        "golden", "indigo", "ivory", "jade", "lunar", "mist", "neon", "onyx",
        "pine", "rust", "sage", "silver", "slate", "solar", "storm", "velvet"
    ]

    private static let animals = [
        "badger", "condor", "crane", "crow", "dove", "eagle", "falcon", "finch",
        "fox", "hare", "heron", "ibis", "jay", "kite", "lynx", "marten",
        "newt", "otter", "owl", "panda", "quail", "raven", "robin", "sparrow",
        "swift", "tiger", "viper", "wolf", "wren", "yak"
    ]

    /// Returns a random adjective-animal nickname, e.g. `cobalt-fox`.
    public static func random() -> String {
        let adjective = adjectives.randomElement() ?? "cobalt"
        let animal = animals.randomElement() ?? "fox"
        return "\(adjective)-\(animal)"
    }

    public static func isValidFormat(_ nickname: String) -> Bool {
        let parts = nickname.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let adj = String(parts[0])
        let animal = String(parts[1])
        return adjectives.contains(adj) && animals.contains(animal)
    }
}
