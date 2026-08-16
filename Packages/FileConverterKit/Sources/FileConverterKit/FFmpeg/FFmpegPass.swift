import Foundation

/// One ffmpeg invocation. Most output types need exactly one; Gif needs two
/// (palette generation, then palette use) — ported from the Windows app's
/// `FFMpegPass` struct (ConversionJob_FFMPEG.cs:545-564).
public struct FFmpegPass: Sendable {
    public let name: String
    public let arguments: [String]
    /// A temp file produced by this pass that should be deleted once the
    /// whole job finishes (e.g. the GIF palette PNG).
    public let fileToDelete: URL?

    public init(name: String = "", arguments: [String], fileToDelete: URL? = nil) {
        self.name = name
        self.arguments = arguments
        self.fileToDelete = fileToDelete
    }
}

public struct FFmpegTransform: Sendable {
    public var scale: Double
    public var rotationDegrees: Int
    /// Force H264-compatible even dimensions + yuv420p, matching
    /// ComputeTransformArgs' special-casing of Mkv/Mp4 output.
    public var forceEvenDimensionsAndYUV420P: Bool

    public init(scale: Double, rotationDegrees: Int, forceEvenDimensionsAndYUV420P: Bool = false) {
        self.scale = scale
        self.rotationDegrees = rotationDegrees
        self.forceEvenDimensionsAndYUV420P = forceEvenDimensionsAndYUV420P
    }

    /// Ported from ComputeTransformArgs (ConversionJob_FFMPEG.Converters.cs:40-118),
    /// minus the CUDA/AMF hardware-acceleration branches (v1 targets
    /// VideoToolbox/CPU only, per the plan).
    public func filterGraph() -> String? {
        var parts: [String] = []

        if forceEvenDimensionsAndYUV420P {
            if abs(scale - 1) >= 0.005 {
                parts.append("scale=trunc(iw*\(formatted(scale))/2)*2:trunc(ih*\(formatted(scale))/2)*2")
            }
        } else if abs(scale - 1) >= 0.005 {
            parts.append("scale=iw*\(formatted(scale)):ih*\(formatted(scale))")
        }

        switch rotationDegrees {
        case 90: parts.append("transpose=2")
        case 180: parts.append("vflip,hflip")
        case 270: parts.append("transpose=1")
        default: break
        }

        if forceEvenDimensionsAndYUV420P {
            parts.append("format=yuv420p")
        }

        return parts.isEmpty ? nil : parts.joined(separator: ",")
    }

    private func formatted(_ value: Double) -> String {
        // Matches the C# "#.##" invariant-culture formatting (up to 2 decimals, no trailing zeros).
        let rounded = (value * 100).rounded() / 100
        return rounded.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(rounded))
            : String(rounded)
    }
}
