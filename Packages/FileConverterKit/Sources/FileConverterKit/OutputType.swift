import Foundation

/// The set of output formats a conversion preset can target.
///
/// Ported 1:1 from the Windows app's `OutputType` enum
/// (Application/FileConverter/OutputType.cs).
public enum OutputType: String, Codable, CaseIterable, Sendable {
    case aac, avi, avif, flac, gif, ico, jpg, mkv, mp3, mp4, ogg, ogv, pdf, png, wav, webm, webp

    /// The file extension written for this output type. Identical to the
    /// raw value for every case here, but kept as a separate accessor so a
    /// future divergence (e.g. "jpg" vs "jpeg") doesn't ripple through call
    /// sites.
    public var fileExtension: String { rawValue }

    /// Which backend job converts to this output type.
    /// Mirrors the dispatch order in ConversionJobFactory.cs:7-57 (extension
    /// of the *input* file is checked first, by the factory; this is the
    /// output-type-only half of that dispatch).
    public var backend: ConversionBackend {
        switch self {
        case .aac, .avi, .flac, .gif, .mkv, .mp3, .mp4, .ogg, .ogv, .wav, .webm:
            return .ffmpeg
        case .ico:
            return .ico // composite: ImageMagick (clamp) -> ffmpeg (mux)
        case .avif, .jpg, .pdf, .png, .webp:
            return .imageMagick
        }
    }
}

public enum ConversionBackend: Sendable {
    case ffmpeg
    case imageMagick
    case ico
}
