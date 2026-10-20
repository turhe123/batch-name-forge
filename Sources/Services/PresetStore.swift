import Foundation

/// Loads and saves rule-stack presets as JSON in Application Support.
enum PresetStore {
    static var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("BatchNameForge", isDirectory: true).appendingPathComponent("presets.json")
    }

    static func load() -> [Preset] {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let presets = try? JSONDecoder().decode([Preset].self, from: data) else { return [] }
        return presets
    }

    static func save(_ presets: [Preset]) throws {
        guard let url = fileURL else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(presets).write(to: url, options: .atomic)
    }
}
