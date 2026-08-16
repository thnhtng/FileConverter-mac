import Foundation

/// Ported 1:1 from ConversionPreset.cs `InitializeDefaultSettings`
/// (lines 411-556) and the built-in preset list in Settings.default.xml.
/// Every numeric default below matches the Windows app so existing users'
/// expectations (e.g. "Mp4 defaults to CRF 23") carry over.
public enum DefaultPresets {
    /// The out-of-the-box settings for a given output type.
    public static func defaultSettings(for outputType: OutputType) -> FormatSettings {
        switch outputType {
        // Audio
        case .aac:
            return .audio(AudioSettings(bitrateKbps: 128, channelCount: 0))
        case .flac:
            return .audio(AudioSettings(bitrateKbps: 0, channelCount: 0))
        case .ogg:
            return .audio(AudioSettings(bitrateKbps: 160, channelCount: 0))
        case .mp3:
            return .audio(AudioSettings(bitrateKbps: 190, channelCount: 0, encodingMode: .mp3VBR))
        case .wav:
            return .audio(AudioSettings(bitrateKbps: 0, channelCount: 0, encodingMode: .wav16))

        // Video
        case .avi:
            return .video(VideoSettings(quality: 20, scale: 1, rotationDegrees: 0, enableAudio: true, audioBitrateKbps: 190))
        case .mkv:
            return .video(VideoSettings(quality: 28, encodingSpeed: .medium, scale: 1, rotationDegrees: 0, enableAudio: true, audioBitrateKbps: 128))
        case .mp4:
            return .video(VideoSettings(quality: 28, encodingSpeed: .medium, scale: 1, rotationDegrees: 0, enableAudio: true, audioBitrateKbps: 128))
        case .ogv:
            return .video(VideoSettings(quality: 7, scale: 1, rotationDegrees: 0, enableAudio: true, audioBitrateKbps: 160))
        case .webm:
            return .video(VideoSettings(quality: 40, scale: 1, rotationDegrees: 0, enableAudio: true, audioBitrateKbps: 160))
        case .gif:
            return .gif(GifSettings(scale: 1, rotationDegrees: 0, framesPerSecond: 15))

        // Images (ImageMagick backend)
        case .avif:
            return .image(ImageSettings(quality: 50, scale: 1, rotationDegrees: 0, clampSizeToPowerOfTwo: false, maximumSizePixels: nil))
        case .png:
            return .image(ImageSettings(quality: 95, scale: 1, rotationDegrees: 0, clampSizeToPowerOfTwo: false, maximumSizePixels: nil))
        case .jpg:
            return .image(ImageSettings(quality: 90, scale: 1, rotationDegrees: 0, clampSizeToPowerOfTwo: false, maximumSizePixels: nil))
        case .webp:
            return .image(ImageSettings(quality: 40, scale: 1, rotationDegrees: 0, clampSizeToPowerOfTwo: false, maximumSizePixels: nil))
        case .ico:
            // Intermediate PNG stage: clamp to a power-of-2 size <= 256px,
            // per ConversionJob_Ico.cs:41-43.
            return .image(ImageSettings(quality: 95, scale: 1, rotationDegrees: 0, clampSizeToPowerOfTwo: true, maximumSizePixels: 256))

        // Documents
        case .pdf:
            return .document(DocumentSettings(densityDpi: 200))
        }
    }

    /// Builds the out-of-the-box preset for a given output type, named
    /// "To <Type>" with input types restricted to whatever's compatible per
    /// `InputCategoryClassifier`.
    public static func preset(for outputType: OutputType) -> ConversionPreset {
        ConversionPreset(
            fullName: "To \(outputType.rawValue.uppercased())",
            outputType: outputType,
            inputTypes: InputCategoryClassifier.compatibleInputExtensions(for: outputType),
            settings: defaultSettings(for: outputType)
        )
    }

    /// The full first-launch preset set: one built-in preset per output
    /// type. (The Windows app also ships scaled/DVD-extraction variants in
    /// Settings.default.xml; those are user-facing conveniences, not
    /// covered 1:1 here — users can duplicate/edit a preset in the UI.)
    public static func builtInPresetSet() -> [ConversionPreset] {
        OutputType.allCases.map(preset(for:))
    }
}
