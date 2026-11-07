import Foundation

/// Global app settings, mirroring the subset of Settings.cs that isn't
/// per-preset. Auto-upgrade/telemetry fields are intentionally omitted
/// (out of scope for v1, per the plan).
public struct AppSettings: Codable, Equatable, Sendable {
    public var maximumSimultaneousConversions: Int
    public var exitApplicationWhenConversionsFinished: Bool
    public var presets: [ConversionPreset]
    /// Spec Check delivery specs. Seeded with `DefaultSpecs.all`.
    public var deliverySpecs: [DeliverySpec]

    public init(
        maximumSimultaneousConversions: Int = max(1, ProcessInfo.processInfo.activeProcessorCount / 2),
        exitApplicationWhenConversionsFinished: Bool = true,
        presets: [ConversionPreset] = DefaultPresets.builtInPresetSet(),
        deliverySpecs: [DeliverySpec] = DefaultSpecs.all
    ) {
        self.maximumSimultaneousConversions = maximumSimultaneousConversions
        self.exitApplicationWhenConversionsFinished = exitApplicationWhenConversionsFinished
        self.presets = presets
        self.deliverySpecs = deliverySpecs
    }

    private enum CodingKeys: String, CodingKey {
        case maximumSimultaneousConversions, exitApplicationWhenConversionsFinished, presets, deliverySpecs
    }

    /// Custom decode so settings.json files written before Spec Check
    /// existed (no `deliverySpecs` key) still load, picking up the defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            maximumSimultaneousConversions: try c.decode(Int.self, forKey: .maximumSimultaneousConversions),
            exitApplicationWhenConversionsFinished: try c.decode(Bool.self, forKey: .exitApplicationWhenConversionsFinished),
            presets: try c.decode([ConversionPreset].self, forKey: .presets),
            deliverySpecs: try c.decodeIfPresent([DeliverySpec].self, forKey: .deliverySpecs) ?? DefaultSpecs.all
        )
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
