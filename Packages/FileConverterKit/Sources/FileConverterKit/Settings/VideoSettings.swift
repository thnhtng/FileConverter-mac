/// Settings for video-family outputs: Avi, Mkv, Mp4, Ogv, Webm.
/// Field names map to ConversionPreset.ConversionSettingKeys in comments.
public struct VideoSettings: Codable, Equatable, Sendable {
    /// VideoQuality. Semantics depend on output type — run through
    /// `FFmpegQualityFormulas` (H264 CRF for Mkv/Mp4, MPEG4 index for Avi,
    /// Theora index for Ogv passed through as-is, VP9 CRF for Webm).
    public var quality: Int

    /// VideoEncodingSpeed. Only used by Mkv/Mp4 (libx264 `-preset`).
    public var encodingSpeed: VideoEncodingSpeed

    /// VideoScale. 1.0 = 100%.
    public var scale: Double

    /// VideoRotation, degrees: 0, 90, 180, or 270.
    public var rotationDegrees: Int

    /// EnableAudio. When false the output has no audio track (`-an`).
    public var enableAudio: Bool

    /// AudioBitrate, used when `enableAudio` is true (routed through AAC or
    /// Vorbis quality tables depending on output type).
    public var audioBitrateKbps: Int

    /// EnableFFMPEGCustomCommand / FFMPEGCustomCommand escape hatch.
    public var customFFmpegCommand: String?

    public init(
        quality: Int,
        encodingSpeed: VideoEncodingSpeed = .medium,
        scale: Double = 1,
        rotationDegrees: Int = 0,
        enableAudio: Bool = true,
        audioBitrateKbps: Int = 128,
        customFFmpegCommand: String? = nil
    ) {
        self.quality = quality
        self.encodingSpeed = encodingSpeed
        self.scale = scale
        self.rotationDegrees = rotationDegrees
        self.enableAudio = enableAudio
        self.audioBitrateKbps = audioBitrateKbps
        self.customFFmpegCommand = customFFmpegCommand
    }
}

/// Ported from Controls/VideoEncodingSpeed.cs — libx264 `-preset` names.
public enum VideoEncodingSpeed: String, Codable, CaseIterable, Sendable {
    case ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow
}

/// Settings for the Gif output type — distinct from VideoSettings because
/// GIF has no audio/quality/encoding-speed knobs, only the 2-pass palette
/// pipeline's frame rate (VideoFramesPerSecond).
public struct GifSettings: Codable, Equatable, Sendable {
    public var scale: Double
    public var rotationDegrees: Int
    public var framesPerSecond: Int

    public init(scale: Double = 1, rotationDegrees: Int = 0, framesPerSecond: Int = 15) {
        self.scale = scale
        self.rotationDegrees = rotationDegrees
        self.framesPerSecond = framesPerSecond
    }
}
