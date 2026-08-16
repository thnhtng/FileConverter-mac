import Foundation

/// Ported from Helpers.cs `InputCategoryNames` / `GetExtensionCategory` /
/// `IsOutputTypeCompatibleWithCategory` (Application/FileConverter/Helpers.cs).
public enum InputCategory: String, Sendable {
    case audio = "Audio"
    case video = "Video"
    case image = "Image"
    case animatedImage = "Animated Image"
    case document = "Document"
    case misc = "Misc"
}

public enum InputCategoryClassifier {
    /// Full list of extensions the Windows app recognizes as convertible
    /// input, lowercase, without the leading dot. Helpers.cs:22-27.
    public static let compatibleInputExtensions: Set<String> = [
        "3gp", "3gpp", "aac", "aiff", "ape", "arw", "avi", "avif", "bik", "bmp", "cda", "cr2", "dds", "dng", "doc", "docx",
        "exr", "flac", "flv", "gif", "heic", "ico", "jfif", "jpg", "jpeg", "m4a", "m4b", "m4v", "mkv", "mov", "mp3", "mp4",
        "mpg", "mpeg", "nef", "odp", "ods", "odt", "oga", "ogg", "ogv", "opus", "pdf", "png", "ppt", "pptx", "psd",
        "raf", "rm", "svg", "tga", "tif", "tiff", "ts", "vob", "wav", "webm", "webp", "wma", "wmv", "xls", "xlsx"
    ]

    private static let audioExtensions: Set<String> = [
        "aac", "aiff", "ape", "cda", "flac", "mp3", "m4a", "m4b", "oga", "ogg", "opus", "wav", "wma"
    ]

    private static let videoExtensions: Set<String> = [
        "3gp", "3gpp", "avi", "bik", "flv", "m4v", "mp4", "mpg", "mpeg", "mov", "mkv", "ogv", "rm", "ts", "vob", "webm", "wmv"
    ]

    private static let imageExtensions: Set<String> = [
        "arw", "avif", "bmp", "cr2", "dds", "dng", "exr", "heic", "ico", "jfif", "jpg", "jpeg",
        "nef", "png", "psd", "raf", "tga", "tif", "tiff", "svg", "xcf", "webp"
    ]

    private static let documentExtensions: Set<String> = [
        "pdf", "doc", "docx", "ppt", "pptx", "odp", "ods", "odt", "xls", "xlsx"
    ]

    /// Helpers.cs:29-108 `GetExtensionCategory`.
    public static func category(forExtension extensionWithoutDot: String) -> InputCategory {
        let ext = extensionWithoutDot.lowercased()
        if audioExtensions.contains(ext) { return .audio }
        if videoExtensions.contains(ext) { return .video }
        if imageExtensions.contains(ext) { return .image }
        if ext == "gif" { return .animatedImage }
        if documentExtensions.contains(ext) { return .document }
        return .misc
    }

    /// Helpers.cs:192-232 `IsOutputTypeCompatibleWithCategory`.
    public static func isOutputType(_ outputType: OutputType, compatibleWith category: InputCategory) -> Bool {
        if category == .misc {
            // Misc is the "unsorted" bucket; be permissive like the Windows app.
            return true
        }

        switch outputType {
        case .aac, .flac, .mp3, .ogg, .wav:
            return category == .audio || category == .video

        case .avi, .mkv, .mp4, .ogv, .webm:
            return category == .video || category == .animatedImage

        case .avif, .ico, .jpg, .png, .webp:
            return category == .image || category == .document || category == .animatedImage

        case .gif:
            return category == .image || category == .video || category == .animatedImage

        case .pdf:
            return category == .image || category == .document
        }
    }

    /// All bundled-input extensions compatible with the given output type —
    /// the set a preset's `inputTypes` should default to. Used by
    /// `DefaultPresets`.
    public static func compatibleInputExtensions(for outputType: OutputType) -> [String] {
        compatibleInputExtensions
            .filter { isOutputType(outputType, compatibleWith: category(forExtension: $0)) }
            .sorted()
    }
}
