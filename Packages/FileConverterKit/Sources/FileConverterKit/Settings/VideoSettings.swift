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

    // MARK: Spec Check fix fields (macOS-only additions)
    //
    // All optional so settings.json files written before Spec Check existed
    // still decode (synthesized Codable uses decodeIfPresent for Optionals).
    // Normally set by `SpecFixPlanner`, not by hand.

    /// Resize/pad/crop the output to an exact frame size.
    public var frameTarget: FrameTarget?

    /// Trim the output to at most this many seconds (`-t`).
    public var maxDurationSeconds: Double?

    /// Force the output frame rate (`fps` filter).
    public var framesPerSecond: Double?

    /// Cap the video bitrate (kbps) so the output fits a file-size limit.
    /// Applied as a VBV cap on top of the quality setting (`-maxrate`/
    /// `-bufsize` for H.264, `-b:v` for VP9) rather than replacing it, so
    /// short/simple clips still come out smaller than the cap.
    public var maxVideoBitrateKbps: Int?

    /// Mux in a silent stereo track when the input has no audio — for
    /// delivery specs that reject video without an audio stream.
    public var addSilentAudioIfMissing: Bool?

    public init(
        quality: Int,
        encodingSpeed: VideoEncodingSpeed = .medium,
        scale: Double = 1,
        rotationDegrees: Int = 0,
        enableAudio: Bool = true,
        audioBitrateKbps: Int = 128,
        customFFmpegCommand: String? = nil,
        frameTarget: FrameTarget? = nil,
        maxDurationSeconds: Double? = nil,
        framesPerSecond: Double? = nil,
        maxVideoBitrateKbps: Int? = nil,
        addSilentAudioIfMissing: Bool? = nil
    ) {
        self.quality = quality
        self.encodingSpeed = encodingSpeed
        self.scale = scale
        self.rotationDegrees = rotationDegrees
        self.enableAudio = enableAudio
        self.audioBitrateKbps = audioBitrateKbps
        self.customFFmpegCommand = customFFmpegCommand
        self.frameTarget = frameTarget
        self.maxDurationSeconds = maxDurationSeconds
        self.framesPerSecond = framesPerSecond
        self.maxVideoBitrateKbps = maxVideoBitrateKbps
        self.addSilentAudioIfMissing = addSilentAudioIfMissing
    }
}

/// How to get from the source frame to an exact target size.
public enum FrameFitMode: String, Codable, CaseIterable, Sendable {
    /// Scale to fit inside the target, fill the rest with bars. Never loses
    /// content — the safe default.
    case pad
    /// Scale to cover the target, cut off what sticks out (center crop).
    case crop
    /// Scale to exactly the target size, distorting if the ratio differs.
    case stretch
}

/// An exact output frame size plus how to fit the source into it.
public struct FrameTarget: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var fitMode: FrameFitMode

    public init(width: Int, height: Int, fitMode: FrameFitMode = .pad) {
        self.width = width
        self.height = height
        self.fitMode = fitMode
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
