import Foundation

private let officeDocumentExtensions: Set<String> = ["doc", "docx", "odt", "xls", "xlsx", "ods", "ppt", "pptx", "odp"]

/// Ported from ConversionJobFactory.cs:7-57 — dispatch is input-extension-
/// first (Office documents always go through LibreOffice regardless of
/// output type), then output-type-based.
///
/// Not ported: `.cda` -> `ConversionJob_ExtractCDA` (physical CD-audio
/// extraction) — no macOS equivalent in scope for this app; presets
/// targeting `.cda` input are simply unsupported for now.
public enum ConversionJobFactory {
    public enum Pipeline: Sendable {
        case ffmpeg
        case imageMagick
        case ico
        case office
        case unsupported(String)
    }

    public static func pipeline(forInputExtension inputExtension: String, outputType: OutputType) -> Pipeline {
        let ext = inputExtension.lowercased()

        if ext == "cda" {
            return .unsupported("CD audio extraction (.cda) isn't supported on macOS yet.")
        }

        if officeDocumentExtensions.contains(ext) {
            return .office
        }

        switch outputType {
        case .ico:
            return .ico
        case .avif, .jpg, .pdf, .png, .webp:
            return .imageMagick
        case .aac, .avi, .flac, .gif, .mkv, .mp3, .mp4, .ogg, .ogv, .wav, .webm:
            return .ffmpeg
        }
    }

    /// Runs the appropriate pipeline end-to-end. Returns every output file
    /// produced (usually one, more for paginated PDF-family conversions).
    @discardableResult
    public static func run(
        preset: ConversionPreset,
        inputURL: URL,
        outputURL: URL,
        progress: ConversionProgressHandler? = nil
    ) async throws -> [URL] {
        switch pipeline(forInputExtension: inputURL.pathExtension, outputType: preset.outputType) {
        case .ffmpeg:
            try await FFmpegConversionExecutor().execute(preset: preset, inputURL: inputURL, outputURL: outputURL, progress: progress)
            return [outputURL]

        case .imageMagick:
            return try await ImageMagickConversionExecutor().execute(preset: preset, inputURL: inputURL, outputURL: outputURL, progress: progress)

        case .ico:
            try await IcoConversionExecutor().execute(preset: preset, inputURL: inputURL, outputURL: outputURL, progress: progress)
            return [outputURL]

        case .office:
            return try await OfficeConversionExecutor().execute(preset: preset, inputURL: inputURL, outputURL: outputURL, progress: progress)

        case .unsupported(let reason):
            throw ConversionJobError.unsupportedPipeline(reason)
        }
    }
}
