import Foundation

public final class SettingsStore {
    private let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(url: URL? = nil) {
        if let url {
            self.url = url
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let directory = support.appendingPathComponent("Spectra", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.url = directory.appendingPathComponent("settings.json")
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() -> UserSettings {
        guard let data = try? Data(contentsOf: url) else {
            return .default
        }
        return (try? decoder.decode(UserSettings.self, from: data)) ?? .default
    }

    public func save(_ settings: UserSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: url, options: [.atomic])
    }
}
