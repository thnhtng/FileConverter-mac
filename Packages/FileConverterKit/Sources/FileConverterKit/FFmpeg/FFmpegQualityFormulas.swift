import Foundation

/// Ported 1:1 from ConversionJob_FFMPEG.Converters.cs. These formulas/tables
/// are the actual reusable domain knowledge from the Windows app — preset
/// compatibility depends on replicating them exactly.
public enum FFmpegQualityFormulas {
    /// H264QualityToCRF. Range 0-51, lower = higher quality.
    public static func h264CRF(quality: Int) -> Int { 51 - quality }

    /// WebmQualityToCRF (VP9). Range 0-63, lower = higher quality.
    public static func webmCRF(quality: Int) -> Int { 63 - quality }

    /// MPEG4QualityToQualityIndex. Range 1-31, lower = higher quality.
    public static func mpeg4QualityIndex(quality: Int) -> Int { 31 - quality }

    /// JPGQualityToQualityIndex (ffmpeg's own mjpeg `-q:v`, distinct from
    /// ImageMagick's `-quality`). Range 1-31, lower = higher quality.
    public static func jpgQualityIndex(quality: Int) -> Int { 31 - quality }

    /// OGVTheoraQualityToQualityIndex — identity, 0-10.
    public static func theoraQualityIndex(quality: Int) -> Int { quality }

    /// MP3VBRBitrateToQualityIndex. Throws-equivalent: returns nil for an
    /// unrecognized bitrate (the Windows app throws; callers here should
    /// treat nil as a validation error).
    public static func mp3VBRQualityIndex(bitrateKbps: Int) -> Int? {
        [245: 0, 225: 1, 190: 2, 175: 3, 165: 4, 130: 5, 115: 6, 100: 7, 85: 8, 65: 9][bitrateKbps]
    }

    /// OGGVBRBitrateToQualityIndex.
    public static func oggVBRQualityIndex(bitrateKbps: Int) -> Int? {
        [500: 10, 320: 9, 256: 8, 224: 7, 192: 6, 160: 5, 128: 4, 112: 3, 96: 2, 80: 1, 64: 0, 48: -1, 32: -2][bitrateKbps]
    }

    /// AACBitrateToQualityIndex — ffmpeg's native AAC encoder `-q:a` takes a
    /// float, hence the string return (matches the C# signature/table).
    public static func aacQualityIndex(bitrateKbps: Int) -> String? {
        [
            460: "3.9", 340: "3", 256: "2.2", 224: "1.9", 192: "1.6", 155: "1.3", 128: "1",
            112: "0.9", 96: "0.75", 80: "0.6", 64: "0.45", 48: "0.3", 32: "0.2", 16: "0.1"
        ][bitrateKbps]
    }

    /// WAVEncodingToCodecArgument.
    public static func wavCodecArgument(_ mode: AudioEncodingMode) -> String {
        switch mode {
        case .wav8: return "pcm_s8le"
        case .wav16: return "pcm_s16le"
        case .wav24: return "pcm_s24le"
        case .wav32: return "pcm_s32le"
        default: return "pcm_s16le"
        }
    }

    /// H264EncodingSpeedToPreset — libx264 `-preset` value.
    public static func h264Preset(_ speed: VideoEncodingSpeed) -> String { speed.rawValue }
}
