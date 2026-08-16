import Foundation

/// Ported from ConversionJob_Ico.cs: image -> PNG (clamped to a power-of-2
/// size, <= 256px) via ImageMagick, then PNG -> ICO via ffmpeg's native ico
/// muxer (no encoder args needed).
public struct IcoConversionExecutor {
    public init() {}

    public func execute(
        preset: ConversionPreset,
        inputURL: URL,
        outputURL: URL,
        progress: ConversionProgressHandler? = nil
    ) async throws {
        let intermediatePNG = UniquePath.generate(
            base: FileManager.default.temporaryDirectory.appendingPathComponent("\(inputURL.lastPathComponent)-ico-intermediate.png")
        )
        defer { try? FileManager.default.removeItem(at: intermediatePNG) }

        var pngPreset = preset
        pngPreset.outputType = .png
        // Settings.image already carries clampSizeToPowerOfTwo=true,
        // maximumSizePixels=256 from DefaultPresets.defaultSettings(.ico).

        try await ImageMagickConversionExecutor().execute(
            preset: pngPreset, inputURL: inputURL, outputURL: intermediatePNG
        ) { fraction in progress?(fraction * 0.5) }

        try await FFmpegConversionExecutor().execute(
            preset: preset, inputURL: intermediatePNG, outputURL: outputURL
        ) { fraction in progress?(0.5 + fraction * 0.5) }
    }
}
