import Foundation

/// Builds `magick` CLI argument lists that approximate the Magick.NET
/// object-model pipeline in ConversionJob_ImageMagick.cs:158-249 (scale ->
/// rotate -> clamp-to-power-of-2 -> clamp-max-size -> format-specific
/// quality). Magick.NET has no macOS equivalent, so this shells out to the
/// ImageMagick CLI instead — see the plan's Phase 1 notes.
///
/// Known gap vs. the Windows app (left as a TODO rather than silently
/// guessed): per-extension `MagickFormat` overrides for raw formats
/// (.cr2/.dng/.arw/...) aren't ported; ImageMagick's own format auto-
/// detection is used instead, which is usually but not always correct.
public enum ImageMagickArgumentBuilder {
    /// Everything needed to run one `magick` invocation, including whether
    /// the output uses ImageMagick's `%d` scene-numbering (multi-page PDF
    /// input) so the caller knows to expect multiple output files.
    public struct Plan: Sendable {
        public let arguments: [String]
        public let producesMultiplePages: Bool
    }

    public static func plan(
        for preset: ConversionPreset,
        inputURL: URL,
        outputURL: URL,
        inputPageCount: Int = 1
    ) throws -> Plan {
        var args: [String] = []

        let isMultiPagePDFInput = inputURL.pathExtension.lowercased() == "pdf" && inputPageCount > 1
        let outputIsPDF = preset.outputType == .pdf

        // Density must precede the input path to affect rasterization of
        // vector/paginated formats (PDF). BaseDpiForPdfConversion = 200,
        // ConversionJob_ImageMagick.cs:12.
        let density = preset.settings.document?.densityDpi ?? 200
        if inputURL.pathExtension.lowercased() == "pdf" || outputIsPDF {
            args += ["-density", "\(density)"]
        }

        args.append(inputURL.path)

        if let image = preset.settings.image {
            if abs(image.scale - 1) >= 0.005 {
                args += ["-resize", "\(Int(image.scale * 100))%"]
            }

            if image.rotationDegrees != 0 {
                args += ["-rotate", "\(image.rotationDegrees)"]
            }

            // Spec Check fix: land on an exact frame size.
            if let target = image.frameTarget, target.width > 0, target.height > 0 {
                args += frameTargetArgs(target)
            }

            // clampSizeToPowerOfTwo: the Ico pipeline's intermediate PNG
            // stage. We don't probe actual pixel dimensions here (that would
            // need a synchronous `identify` round-trip); ImageMagick's
            // `-resize NxN>` with the settings' maximumSizePixels (256 for
            // the Ico preset) already bounds the output, and %-based `-resize`
            // above handles arbitrary scaling. A true "round down to nearest
            // power of two" step is a fast-follow — see IcoConversionExecutor.
            if let maxSize = image.maximumSizePixels {
                args += ["-resize", "\(maxSize)x\(maxSize)>"]
            }

            if preset.outputType != .png {
                args += ["-quality", "\(image.quality)"]
            } else {
                // ConversionJob_ImageMagick.cs:224-225: PNG "quality" in
                // ImageMagick controls zlib compression effort, not visual
                // fidelity — hardcoded to 95 regardless of user settings.
                args += ["-quality", "95"]
            }
        } else if outputIsPDF {
            args += ["-quality", "95"]
        }

        if isMultiPagePDFInput {
            let ext = outputURL.pathExtension
            let stem = outputURL.deletingPathExtension().lastPathComponent
            let pattern = outputURL.deletingLastPathComponent().appendingPathComponent("\(stem)-%02d.\(ext)")
            args.append(pattern.path)
            return Plan(arguments: args, producesMultiplePages: true)
        }

        args.append(outputURL.path)
        return Plan(arguments: args, producesMultiplePages: false)
    }

    /// `-extent` after a fit/cover `-resize` = pad/crop to the exact size,
    /// centered. `+repage` drops the virtual canvas offset so formats that
    /// store it (PNG, GIF) don't report a stale page geometry.
    static func frameTargetArgs(_ target: FrameTarget) -> [String] {
        let size = "\(target.width)x\(target.height)"
        switch target.fitMode {
        case .pad:
            return ["-resize", size, "-background", "black", "-gravity", "center", "-extent", size, "+repage"]
        case .crop:
            return ["-resize", "\(size)^", "-gravity", "center", "-extent", size, "+repage"]
        case .stretch:
            return ["-resize", "\(size)!"]
        }
    }
}
