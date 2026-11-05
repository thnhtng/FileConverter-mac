import Foundation

/// Which rule of a `DeliverySpec` a finding is about.
public enum SpecRule: String, Codable, CaseIterable, Sendable {
    case mediaKind
    case fileFormat
    case fileSize
    case dimensions
    case aspectRatio
    case duration
    case frameRate
    case videoCodec
    case audioCodec
    case audioTrack

    public var title: String {
        switch self {
        case .mediaKind: return "Media type"
        case .fileFormat: return "File format"
        case .fileSize: return "File size"
        case .dimensions: return "Dimensions"
        case .aspectRatio: return "Aspect ratio"
        case .duration: return "Duration"
        case .frameRate: return "Frame rate"
        case .videoCodec: return "Video codec"
        case .audioCodec: return "Audio codec"
        case .audioTrack: return "Audio track"
        }
    }
}

public enum SpecFindingStatus: String, Codable, Comparable, Sendable {
    case pass
    /// The value couldn't be read, so the rule couldn't be verified —
    /// a human should look.
    case warning
    case fail

    private var severity: Int {
        switch self {
        case .pass: return 0
        case .warning: return 1
        case .fail: return 2
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.severity < rhs.severity }
}

/// One rule's verdict for one file: what the spec wanted, what the file has.
public struct SpecFinding: Codable, Equatable, Identifiable, Sendable {
    public var rule: SpecRule
    public var status: SpecFindingStatus
    public var expected: String
    public var actual: String

    public var id: SpecRule { rule }

    public init(rule: SpecRule, status: SpecFindingStatus, expected: String, actual: String) {
        self.rule = rule
        self.status = status
        self.expected = expected
        self.actual = actual
    }
}

/// All findings for one file against one spec.
public struct SpecCheckResult: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var info: MediaInfo
    public var specID: UUID
    public var specName: String
    public var findings: [SpecFinding]

    public init(id: UUID = UUID(), info: MediaInfo, spec: DeliverySpec, findings: [SpecFinding]) {
        self.id = id
        self.info = info
        self.specID = spec.id
        self.specName = spec.name
        self.findings = findings
    }

    /// Worst status across findings (pass when there are no rules).
    public var status: SpecFindingStatus { findings.map(\.status).max() ?? .pass }
    public var failures: [SpecFinding] { findings.filter { $0.status == .fail } }
    public var warnings: [SpecFinding] { findings.filter { $0.status == .warning } }
    public var passed: Bool { status != .fail }
}

/// Evaluates a `MediaInfo` against a `DeliverySpec`. Pure and synchronous —
/// all I/O happens in `MediaProbe` — so every rule is unit-testable with
/// hand-built `MediaInfo` values.
public enum SpecChecker {
    private static let unknown = "Unknown"

    public static func check(_ info: MediaInfo, against spec: DeliverySpec) -> SpecCheckResult {
        var findings: [SpecFinding] = []

        // Media kind first: if it's the wrong kind of file, the per-kind
        // rules below would only add noise.
        if !spec.mediaKinds.isEmpty {
            let ok = spec.mediaKinds.contains(info.kind)
            findings.append(SpecFinding(
                rule: .mediaKind,
                status: ok ? .pass : .fail,
                expected: spec.mediaKinds.map(\.rawValue).joined(separator: " or "),
                actual: info.kind.rawValue
            ))
            if !ok { return SpecCheckResult(info: info, spec: spec, findings: findings) }
        }

        if let exts = spec.allowedExtensions, !exts.isEmpty {
            let ext = DeliverySpec.normalizedExtension(info.fileExtension)
            findings.append(SpecFinding(
                rule: .fileFormat,
                status: exts.contains(ext) ? .pass : .fail,
                expected: exts.map { ".\($0)" }.joined(separator: ", "),
                actual: ext.isEmpty ? "(no extension)" : ".\(ext)"
            ))
        }

        if let maxMB = spec.maxFileSizeMB {
            findings.append(SpecFinding(
                rule: .fileSize,
                status: info.fileSizeMB <= maxMB ? .pass : .fail,
                expected: "≤ \(SpecFormat.megabytes(maxMB))",
                actual: SpecFormat.megabytes(info.fileSizeMB)
            ))
        }

        let isVisual = info.kind == .video || info.kind == .image
        if isVisual, let finding = dimensionsFinding(info, spec) { findings.append(finding) }
        if isVisual, let finding = aspectRatioFinding(info, spec) { findings.append(finding) }

        let isTimed = info.kind == .video || info.kind == .audio
        if isTimed, spec.minDurationSeconds != nil || spec.maxDurationSeconds != nil {
            findings.append(rangeFinding(
                rule: .duration, value: info.durationSeconds,
                min: spec.minDurationSeconds, max: spec.maxDurationSeconds,
                format: SpecFormat.seconds
            ))
        }

        if info.kind == .video, spec.minFramesPerSecond != nil || spec.maxFramesPerSecond != nil {
            // Allow tiny drift: 29.97 counts as 30 for a "≤ 30 fps" rule.
            findings.append(rangeFinding(
                rule: .frameRate, value: info.framesPerSecond,
                min: spec.minFramesPerSecond.map { $0 - 0.05 }, max: spec.maxFramesPerSecond.map { $0 + 0.05 },
                displayMin: spec.minFramesPerSecond, displayMax: spec.maxFramesPerSecond,
                format: SpecFormat.fps
            ))
        }

        if info.kind == .video, let codecs = spec.allowedVideoCodecs, !codecs.isEmpty {
            findings.append(codecFinding(rule: .videoCodec, actual: info.videoCodec, allowed: codecs))
        }

        if isTimed {
            switch spec.audio {
            case .optional:
                break
            case .required:
                findings.append(SpecFinding(
                    rule: .audioTrack, status: info.hasAudio ? .pass : .fail,
                    expected: "Has audio", actual: info.hasAudio ? "Has audio" : "No audio"
                ))
            case .forbidden:
                findings.append(SpecFinding(
                    rule: .audioTrack, status: info.hasAudio ? .fail : .pass,
                    expected: "No audio", actual: info.hasAudio ? "Has audio" : "No audio"
                ))
            }

            if info.hasAudio, let codecs = spec.allowedAudioCodecs, !codecs.isEmpty {
                findings.append(codecFinding(rule: .audioCodec, actual: info.audioCodec, allowed: codecs))
            }
        }

        return SpecCheckResult(info: info, spec: spec, findings: findings)
    }

    // MARK: - Rules

    private static func dimensionsFinding(_ info: MediaInfo, _ spec: DeliverySpec) -> SpecFinding? {
        let hasExact = spec.width != nil || spec.height != nil
        let hasBounds = [spec.minWidth, spec.minHeight, spec.maxWidth, spec.maxHeight].contains { $0 != nil }
        guard hasExact || hasBounds else { return nil }

        var expectedParts: [String] = []
        if hasExact {
            expectedParts.append("\(spec.width.map(String.init) ?? "any") × \(spec.height.map(String.init) ?? "any")")
        } else {
            if spec.minWidth != nil || spec.minHeight != nil {
                expectedParts.append("≥ \(spec.minWidth.map(String.init) ?? "any") × \(spec.minHeight.map(String.init) ?? "any")")
            }
            if spec.maxWidth != nil || spec.maxHeight != nil {
                expectedParts.append("≤ \(spec.maxWidth.map(String.init) ?? "any") × \(spec.maxHeight.map(String.init) ?? "any")")
            }
        }
        let expected = expectedParts.joined(separator: ", ")

        guard let width = info.displayWidth, let height = info.displayHeight else {
            return SpecFinding(rule: .dimensions, status: .warning, expected: expected, actual: unknown)
        }

        var ok = true
        if hasExact {
            if let w = spec.width, w != width { ok = false }
            if let h = spec.height, h != height { ok = false }
        } else {
            if let v = spec.minWidth, width < v { ok = false }
            if let v = spec.minHeight, height < v { ok = false }
            if let v = spec.maxWidth, width > v { ok = false }
            if let v = spec.maxHeight, height > v { ok = false }
        }
        return SpecFinding(rule: .dimensions, status: ok ? .pass : .fail, expected: expected, actual: "\(width) × \(height)")
    }

    private static func aspectRatioFinding(_ info: MediaInfo, _ spec: DeliverySpec) -> SpecFinding? {
        guard let ratios = spec.aspectRatios, !ratios.isEmpty else { return nil }
        let expected = ratios.map(\.description).joined(separator: " or ")
        guard let width = info.displayWidth, let height = info.displayHeight, width > 0, height > 0 else {
            return SpecFinding(rule: .aspectRatio, status: .warning, expected: expected, actual: unknown)
        }
        let actualValue = Double(width) / Double(height)
        let ok = ratios.contains { abs(actualValue - $0.value) <= $0.value * spec.aspectRatioTolerance }
        return SpecFinding(
            rule: .aspectRatio, status: ok ? .pass : .fail,
            expected: expected, actual: describeRatio(width: width, height: height)
        )
    }

    /// "16:9" for 1920×1080, otherwise the reduced fraction or a decimal
    /// ("1.78:1") when the numbers are unwieldy.
    static func describeRatio(width: Int, height: Int) -> String {
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        let divisor = max(1, gcd(width, height))
        let w = width / divisor, h = height / divisor
        if w <= 32 && h <= 32 { return "\(w):\(h)" }
        return "\(SpecFormat.number(Double(width) / Double(height))):1"
    }

    private static func rangeFinding(
        rule: SpecRule,
        value: Double?,
        min: Double?,
        max: Double?,
        displayMin: Double? = nil,
        displayMax: Double? = nil,
        format: (Double) -> String
    ) -> SpecFinding {
        let shownMin = displayMin ?? min
        let shownMax = displayMax ?? max
        let expected: String
        switch (shownMin, shownMax) {
        case let (lo?, hi?): expected = "\(format(lo)) – \(format(hi))"
        case let (lo?, nil): expected = "≥ \(format(lo))"
        case let (nil, hi?): expected = "≤ \(format(hi))"
        case (nil, nil): expected = "Any"
        }
        guard let value else {
            return SpecFinding(rule: rule, status: .warning, expected: expected, actual: unknown)
        }
        var ok = true
        if let min, value < min { ok = false }
        if let max, value > max { ok = false }
        return SpecFinding(rule: rule, status: ok ? .pass : .fail, expected: expected, actual: format(value))
    }

    private static func codecFinding(rule: SpecRule, actual: String?, allowed: [String]) -> SpecFinding {
        let expected = allowed.joined(separator: ", ")
        guard let actual, !actual.isEmpty else {
            return SpecFinding(rule: rule, status: .warning, expected: expected, actual: unknown)
        }
        let ok = allowed.contains(actual.lowercased())
        return SpecFinding(rule: rule, status: ok ? .pass : .fail, expected: expected, actual: actual)
    }
}

/// Probe + check in one call — what the UI runs per dropped file.
public enum SpecCheckService {
    public static func check(_ url: URL, against spec: DeliverySpec) async throws -> SpecCheckResult {
        let info = try await MediaProbe.probe(url)
        return SpecChecker.check(info, against: spec)
    }
}
