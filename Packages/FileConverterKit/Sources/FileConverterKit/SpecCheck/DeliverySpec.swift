import Foundation

/// A width:height ratio such as 9:16.
public struct AspectRatio: Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// Parses "9:16", "9x16" or "9/16".
    public init?(string: String) {
        let parts = string.split(whereSeparator: { $0 == ":" || $0 == "x" || $0 == "/" })
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
        self.init(width: parts[0], height: parts[1])
    }

    public var value: Double { height == 0 ? 0 : Double(width) / Double(height) }
    public var description: String { "\(width):\(height)" }

    public static let vertical9x16 = AspectRatio(width: 9, height: 16)
    public static let landscape16x9 = AspectRatio(width: 16, height: 9)
    public static let square1x1 = AspectRatio(width: 1, height: 1)
    public static let portrait4x5 = AspectRatio(width: 4, height: 5)
}

/// Whether a delivery needs an audio track.
public enum AudioRequirement: String, Codable, CaseIterable, Sendable {
    case optional
    case required
    case forbidden
}

/// A named set of rules a file must meet before it's sent somewhere — an
/// ad network's creative spec, a store's screenshot size, a "max 25 MB in
/// chat" house rule. Every rule is optional; nil means "don't care".
///
/// Decoding is deliberately lenient (missing keys and explicit nulls both
/// become "no rule") so hand-edited JSON and AI-drafted specs
/// (`ClaudeSpecImporter`) load without ceremony.
public struct DeliverySpec: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var notes: String?

    /// Media kinds this spec is for. Empty = any kind.
    public var mediaKinds: [MediaKind]
    /// Lowercased extensions without the dot. nil/empty = any.
    public var allowedExtensions: [String]?
    public var maxFileSizeMB: Double?

    /// Exact display size. Takes precedence over the min/max bounds below.
    public var width: Int?
    public var height: Int?
    public var minWidth: Int?
    public var minHeight: Int?
    public var maxWidth: Int?
    public var maxHeight: Int?

    /// Allowed display aspect ratios. nil/empty = any.
    public var aspectRatios: [AspectRatio]?
    /// Relative tolerance for aspect-ratio matching (0.01 = 1%).
    public var aspectRatioTolerance: Double

    public var minDurationSeconds: Double?
    public var maxDurationSeconds: Double?
    public var minFramesPerSecond: Double?
    public var maxFramesPerSecond: Double?

    /// ffprobe codec names, lowercased ("h264", "hevc", "vp9", "aac"...).
    public var allowedVideoCodecs: [String]?
    public var allowedAudioCodecs: [String]?
    public var audio: AudioRequirement

    /// True for the built-in examples, so the UI can offer "reset".
    public var isBuiltIn: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        notes: String? = nil,
        mediaKinds: [MediaKind] = [],
        allowedExtensions: [String]? = nil,
        maxFileSizeMB: Double? = nil,
        width: Int? = nil,
        height: Int? = nil,
        minWidth: Int? = nil,
        minHeight: Int? = nil,
        maxWidth: Int? = nil,
        maxHeight: Int? = nil,
        aspectRatios: [AspectRatio]? = nil,
        aspectRatioTolerance: Double = 0.01,
        minDurationSeconds: Double? = nil,
        maxDurationSeconds: Double? = nil,
        minFramesPerSecond: Double? = nil,
        maxFramesPerSecond: Double? = nil,
        allowedVideoCodecs: [String]? = nil,
        allowedAudioCodecs: [String]? = nil,
        audio: AudioRequirement = .optional,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.mediaKinds = mediaKinds
        self.allowedExtensions = allowedExtensions?.map { Self.normalizedExtension($0) }
        self.maxFileSizeMB = maxFileSizeMB
        self.width = width
        self.height = height
        self.minWidth = minWidth
        self.minHeight = minHeight
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.aspectRatios = aspectRatios
        self.aspectRatioTolerance = aspectRatioTolerance
        self.minDurationSeconds = minDurationSeconds
        self.maxDurationSeconds = maxDurationSeconds
        self.minFramesPerSecond = minFramesPerSecond
        self.maxFramesPerSecond = maxFramesPerSecond
        self.allowedVideoCodecs = allowedVideoCodecs?.map { $0.lowercased() }
        self.allowedAudioCodecs = allowedAudioCodecs?.map { $0.lowercased() }
        self.audio = audio
        self.isBuiltIn = isBuiltIn
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, notes, mediaKinds, allowedExtensions, maxFileSizeMB
        case width, height, minWidth, minHeight, maxWidth, maxHeight
        case aspectRatios, aspectRatioTolerance
        case minDurationSeconds, maxDurationSeconds, minFramesPerSecond, maxFramesPerSecond
        case allowedVideoCodecs, allowedAudioCodecs, audio, isBuiltIn
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            name: try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled spec",
            notes: try c.decodeIfPresent(String.self, forKey: .notes),
            mediaKinds: try c.decodeIfPresent([MediaKind].self, forKey: .mediaKinds) ?? [],
            allowedExtensions: try c.decodeIfPresent([String].self, forKey: .allowedExtensions),
            maxFileSizeMB: try c.decodeIfPresent(Double.self, forKey: .maxFileSizeMB),
            width: try c.decodeIfPresent(Int.self, forKey: .width),
            height: try c.decodeIfPresent(Int.self, forKey: .height),
            minWidth: try c.decodeIfPresent(Int.self, forKey: .minWidth),
            minHeight: try c.decodeIfPresent(Int.self, forKey: .minHeight),
            maxWidth: try c.decodeIfPresent(Int.self, forKey: .maxWidth),
            maxHeight: try c.decodeIfPresent(Int.self, forKey: .maxHeight),
            aspectRatios: try c.decodeIfPresent([AspectRatio].self, forKey: .aspectRatios),
            aspectRatioTolerance: try c.decodeIfPresent(Double.self, forKey: .aspectRatioTolerance) ?? 0.01,
            minDurationSeconds: try c.decodeIfPresent(Double.self, forKey: .minDurationSeconds),
            maxDurationSeconds: try c.decodeIfPresent(Double.self, forKey: .maxDurationSeconds),
            minFramesPerSecond: try c.decodeIfPresent(Double.self, forKey: .minFramesPerSecond),
            maxFramesPerSecond: try c.decodeIfPresent(Double.self, forKey: .maxFramesPerSecond),
            allowedVideoCodecs: try c.decodeIfPresent([String].self, forKey: .allowedVideoCodecs),
            allowedAudioCodecs: try c.decodeIfPresent([String].self, forKey: .allowedAudioCodecs),
            audio: try c.decodeIfPresent(AudioRequirement.self, forKey: .audio) ?? .optional,
            isBuiltIn: try c.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        )
    }

    static func normalizedExtension(_ ext: String) -> String {
        var value = ext.trimmingCharacters(in: .whitespaces).lowercased()
        if value.hasPrefix(".") { value.removeFirst() }
        return value == "jpeg" ? "jpg" : value
    }

    /// One-line human summary, e.g. "1080×1920 · 9:16 · ≤ 60 s · ≤ 30 MB".
    public var summary: String {
        var parts: [String] = []
        if let width, let height { parts.append("\(width)×\(height)") }
        if let ratios = aspectRatios, !ratios.isEmpty { parts.append(ratios.map(\.description).joined(separator: " / ")) }
        if let maxDurationSeconds { parts.append("≤ \(SpecFormat.seconds(maxDurationSeconds))") }
        if let maxFileSizeMB { parts.append("≤ \(SpecFormat.megabytes(maxFileSizeMB))") }
        if let exts = allowedExtensions, !exts.isEmpty { parts.append(exts.joined(separator: "/")) }
        return parts.isEmpty ? "No rules" : parts.joined(separator: " · ")
    }
}

/// Number formatting shared by spec summaries, findings and reports.
public enum SpecFormat {
    public static func number(_ value: Double, maxDecimals: Int = 2) -> String {
        let factor = pow(10, Double(maxDecimals))
        let rounded = (value * factor).rounded() / factor
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        var text = String(format: "%.\(maxDecimals)f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    public static func seconds(_ value: Double) -> String { "\(number(value, maxDecimals: 1)) s" }
    public static func megabytes(_ value: Double) -> String { "\(number(value, maxDecimals: 2)) MB" }
    public static func fps(_ value: Double) -> String { "\(number(value, maxDecimals: 2)) fps" }
}
