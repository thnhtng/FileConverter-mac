import Foundation

/// Global app settings, mirroring the subset of Settings.cs that isn't
/// per-preset. Auto-upgrade/telemetry fields are intentionally omitted
/// (out of scope for v1, per the plan).
public struct AppSettings: Codable, Equatable, Sendable {
    public var maximumSimultaneousConversions: Int
    public var exitApplicationWhenConversionsFinished: Bool
    public var presets: [ConversionPreset]

    public init(
        maximumSimultaneousConversions: Int = max(1, ProcessInfo.processInfo.activeProcessorCount / 2),
        exitApplicationWhenConversionsFinished: Bool = true,
        presets: [ConversionPreset] = DefaultPresets.builtInPresetSet()
    ) {
        self.maximumSimultaneousConversions = maximumSimultaneousConversions
        self.exitApplicationWhenConversionsFinished = exitApplicationWhenConversionsFinished
        self.presets = presets
    }
}

/// JSON persistence at ~/Library/Application Support/File Converter/settings.json.
/// Replaces the Windows app's Settings.xml (Settings.cs / Settings.default.xml)
/// — see the plan's Phase 1 "Settings persistence" note on why JSON instead
/// of XML for the native format, with XML import as a possible fast-follow.
public enum SettingsStore {
    public static var defaultStoreURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("File Converter", isDirectory: true).appendingPathComponent("settings.json")
    }()

    /// Loads settings from `url`, seeding it with the built-in preset set on
    /// first launch if the file doesn't exist yet — replaces the Windows
    /// app's `--post-install-init` step (SettingsService.cs).
    public static func loadOrSeed(url: URL = defaultStoreURL) throws -> AppSettings {
        if let data = try? Data(contentsOf: url) {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        }
        let settings = AppSettings()
        try save(settings, to: url)
        return settings
    }

    public static func save(_ settings: AppSettings, to url: URL = defaultStoreURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: url, options: .atomic)
    }
}
