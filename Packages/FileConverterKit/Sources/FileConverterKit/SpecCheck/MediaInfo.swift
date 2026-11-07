import Foundation

/// What kind of media a file is, as far as delivery specs care.
public enum MediaKind: String, Codable, CaseIterable, Sendable {
    case video, audio, image, document, other
}

/// Everything Spec Check knows about one file. Produced by `MediaProbe`
/// (ffprobe / ImageMagick) and evaluated by `SpecChecker`. Any property can
/// be nil when the backend couldn't read it — the checker reports that as a
/// warning instead of guessing.
public struct MediaInfo: Codable, Equatable, Sendable {
    public var fileURL: URL
    public var fileSizeBytes: Int64
    public var kind: MediaKind
    /// ffprobe's `format_name`, e.g. "mov,mp4,m4a,3gp,3g2,mj2".
    public var containerFormat: String?

    /// Coded (storage) frame size. Use `displayWidth`/`displayHeight` for
    /// checks — phone videos are often stored landscape with a rotation flag.
    public var width: Int?
    public var height: Int?
    /// Display rotation in degrees (0/90/180/270), from the display matrix
    /// side data or the legacy `rotate` tag.
    public var rotationDegrees: Int

    public var durationSeconds: Double?
    public var framesPerSecond: Double?
    public var videoCodec: String?
    public var audioCodec: String?
    public var hasAudio: Bool
    public var bitrateKbps: Int?

    public init(
        fileURL: URL,
        fileSizeBytes: Int64,
        kind: MediaKind,
        containerFormat: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        rotationDegrees: Int = 0,
        durationSeconds: Double? = nil,
        framesPerSecond: Double? = nil,
        videoCodec: String? = nil,
        audioCodec: String? = nil,
        hasAudio: Bool = false,
        bitrateKbps: Int? = nil
    ) {
        self.fileURL = fileURL
        self.fileSizeBytes = fileSizeBytes
        self.kind = kind
        self.containerFormat = containerFormat
        self.width = width
        self.height = height
        self.rotationDegrees = rotationDegrees
        self.durationSeconds = durationSeconds
        self.framesPerSecond = framesPerSecond
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.hasAudio = hasAudio
        self.bitrateKbps = bitrateKbps
    }

    /// Lowercased extension without the dot.
    public var fileExtension: String { fileURL.pathExtension.lowercased() }

    /// Size in MB (1 MB = 1,000,000 bytes — the stricter reading of the
    /// limits platforms publish, so a "pass" here is a pass there too).
    public var fileSizeMB: Double { Double(fileSizeBytes) / 1_000_000 }

    private var isQuarterTurn: Bool { rotationDegrees == 90 || rotationDegrees == 270 }

    /// Width as the viewer sees it (rotation applied).
    public var displayWidth: Int? { isQuarterTurn ? height : width }
    /// Height as the viewer sees it (rotation applied).
    public var displayHeight: Int? { isQuarterTurn ? width : height }
}
