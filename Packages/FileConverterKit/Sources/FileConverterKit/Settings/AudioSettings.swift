/// Settings for audio-family outputs: Aac, Flac, Mp3, Ogg, Wav.
///
/// Replaces the Windows app's stringly-typed `Dictionary<string,string>`
/// (ConversionPreset.ConversionSettingKeys) with a typed struct per the
/// plan's Phase 1 design decision. Field names map to the original setting
/// keys in comments for traceability.
public struct AudioSettings: Codable, Equatable, Sendable {
    /// AudioBitrate. Meaning depends on `encodingMode`/output type — for
    /// Mp3/Ogg it indexes the VBR quality tables in `FFmpegQualityFormulas`;
    /// for Aac it's fed through `FFmpegQualityFormulas.aacQualityIndex`.
    /// Ignored for Flac (always max compression) and Wav (PCM, no bitrate).
    public var bitrateKbps: Int

    /// AudioChannelCount. 0 = keep the source channel layout (`-ac` omitted).
    public var channelCount: Int

    /// AudioEncodingMode. Only meaningful for Mp3 (vbr/cbr) and Wav (pcm bit depth).
    public var encodingMode: AudioEncodingMode

    /// Mp3/Ogg/Aac only: raw ffmpeg arguments spliced in place of the normal
    /// encoder args (EnableFFMPEGCustomCommand / FFMPEGCustomCommand).
    public var customFFmpegCommand: String?

    public init(
        bitrateKbps: Int,
        channelCount: Int = 0,
        encodingMode: AudioEncodingMode = .mp3VBR,
        customFFmpegCommand: String? = nil
    ) {
        self.bitrateKbps = bitrateKbps
        self.channelCount = channelCount
        self.encodingMode = encodingMode
        self.customFFmpegCommand = customFFmpegCommand
    }
}

/// Ported from Controls/EncodingMode.cs.
public enum AudioEncodingMode: String, Codable, Sendable {
    case mp3VBR
    case mp3CBR
    case wav8, wav16, wav24, wav32
}
