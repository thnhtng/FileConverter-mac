import Foundation

/// Ported from ConversionJob.cs `PrepareConversion` (lines 214-321) and
/// `OnConversionSucceed`/`ChangeOutputFileTimestampToMatchOriginal` (416-506):
/// output path generation from the template, same-path collision handling,
/// timestamp preservation, and the post-conversion action.
///
/// Template support is intentionally minimal for v1 — only the `(p)` parent
/// path and `(f)` filename-without-extension tokens are implemented (every
/// built-in preset uses "(p)(f)"). The Windows app's `(n:i)`/`(n:c)`
/// page-index tokens for multi-page outputs are a fast-follow; multi-page
/// jobs here fall back to ImageMagick's own `-NN` numbering instead
/// (see `ImageMagickArgumentBuilder`).
public enum ConversionOutputPlanner {
    /// Computes the (unique, not-yet-existing) output path for a single-file
    /// conversion.
    public static func outputURL(for inputURL: URL, preset: ConversionPreset) -> URL {
        let parentDirectory = inputURL.deletingLastPathComponent()
        let stem = inputURL.deletingPathExtension().lastPathComponent

        var name = preset.outputFileNameTemplate
        name = name.replacingOccurrences(of: "(p)", with: "")
        name = name.replacingOccurrences(of: "(f)", with: stem)

        let candidate = parentDirectory
            .appendingPathComponent(name)
            .appendingPathExtension(preset.outputType.fileExtension)

        return UniquePath.generate(base: candidate)
    }

    /// If the computed output path collides with the input path (converting
    /// in place, e.g. with a Move/Delete post-conversion action), rename the
    /// input to a `_TEMP` sibling first so the final output can reuse the
    /// original name — ConversionJob.cs:256-266.
    public static func resolveCollision(inputURL: URL, outputURL: URL) throws -> (effectiveInputURL: URL, cleanupTempInput: (() -> Void)?) {
        guard inputURL.path == outputURL.path else { return (inputURL, nil) }

        let tempURL = inputURL.deletingPathExtension()
            .appendingPathExtension("_TEMP")
            .appendingPathExtension(inputURL.pathExtension)
        try FileManager.default.moveItem(at: inputURL, to: tempURL)

        return (tempURL, { try? FileManager.default.removeItem(at: tempURL) })
    }

    /// Copies creation/modification dates from the input to every output
    /// file — ConversionJob.cs `ChangeOutputFileTimestampToMatchOriginal`.
    public static func copyTimestamps(from inputURL: URL, to outputURLs: [URL]) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: inputURL.path) else { return }
        var newAttrs: [FileAttributeKey: Any] = [:]
        if let created = attrs[.creationDate] { newAttrs[.creationDate] = created }
        if let modified = attrs[.modificationDate] { newAttrs[.modificationDate] = modified }
        guard !newAttrs.isEmpty else { return }
        for url in outputURLs {
            try? FileManager.default.setAttributes(newAttrs, ofItemAtPath: url.path)
        }
    }

    /// Deletes any output files that did get created before a failure —
    /// ConversionJob.cs `OnConversionFailed`.
    public static func cleanUpPartialOutputs(_ urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Applies the preset's `InputPostConversionAction` after a successful
    /// conversion.
    public static func applyPostConversionAction(_ action: InputPostConversionAction, to inputURL: URL) throws {
        switch action {
        case .none:
            break
        case .delete:
            try FileManager.default.removeItem(at: inputURL)
        case .moveInArchiveFolder:
            let archiveDir = inputURL.deletingLastPathComponent().appendingPathComponent("Converted", isDirectory: true)
            try FileManager.default.createDirectory(at: archiveDir, withIntermediateDirectories: true)
            let destination = UniquePath.generate(base: archiveDir.appendingPathComponent(inputURL.lastPathComponent))
            try FileManager.default.moveItem(at: inputURL, to: destination)
        }
    }
}
