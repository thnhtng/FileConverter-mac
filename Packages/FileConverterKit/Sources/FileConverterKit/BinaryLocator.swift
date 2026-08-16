import Foundation

/// Locates the CLI backends. Mirrors the Windows app's `FfmpegPath`
/// (ConversionJob_FFMPEG.cs:50-57: "next to the executing assembly") — here,
/// look inside the app bundle's Resources first (Phase 0/4 plan: bundle
/// static universal ffmpeg/ImageMagick builds), then fall back to common
/// Homebrew install locations for development builds where nothing's
/// bundled yet.
public enum BinaryLocator {
    public enum Tool: String {
        case ffmpeg
        case ffprobe
        case magick
        /// LibreOffice is never bundled (too large, per the plan) — always
        /// detected on the system.
        case soffice
    }

    public static func locate(_ tool: Tool) -> URL? {
        if let bundled = bundledPath(for: tool) { return bundled }
        return systemPath(for: tool)
    }

    private static func bundledPath(for tool: Tool) -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let candidate = resourceURL.appendingPathComponent(tool.rawValue)
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }

    private static func systemPath(for tool: Tool) -> URL? {
        let searchPaths: [String]
        switch tool {
        case .soffice:
            searchPaths = [
                "/Applications/LibreOffice.app/Contents/MacOS/soffice",
                "/opt/homebrew/bin/soffice",
                "/usr/local/bin/soffice"
            ]
        default:
            searchPaths = [
                "/opt/homebrew/bin/\(tool.rawValue)",
                "/usr/local/bin/\(tool.rawValue)",
                "/usr/bin/\(tool.rawValue)"
            ]
        }

        for path in searchPaths where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    /// True if LibreOffice is installed — gates whether Office-family
    /// presets (doc/docx/xls.../ppt... -> pdf) can run. See Phase 0's
    /// "detect an existing /Applications/LibreOffice.app" decision.
    public static var isLibreOfficeAvailable: Bool { locate(.soffice) != nil }
}
