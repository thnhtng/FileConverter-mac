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

    /// Spec Check fix: exact output frame size (pad/crop/stretch).
    public var frameTarget: FrameTarget?
    /// Spec Check fix: forced output frame rate.
    public var framesPerSecond: Double?

    public init(
        scale: Double,
        rotationDegrees: Int,
        forceEvenDimensionsAndYUV420P: Bool = false,
        frameTarget: FrameTarget? = nil,
        framesPerSecond: Double? = nil
    ) {
        self.scale = scale
        self.rotationDegrees = rotationDegrees
        self.forceEvenDimensionsAndYUV420P = forceEvenDimensionsAndYUV420P
        self.frameTarget = frameTarget
        self.framesPerSecond = framesPerSecond
    }

    /// Convenience for the video output types: pulls scale/rotation and the
    /// Spec Check fix fields out of `VideoSettings`.
    public init(video: VideoSettings, forceEvenDimensionsAndYUV420P: Bool = false) {
        self.init(
            scale: video.scale,
            rotationDegrees: video.rotationDegrees,
            forceEvenDimensionsAndYUV420P: forceEvenDimensionsAndYUV420P,
            frameTarget: video.frameTarget,
            framesPerSecond: video.framesPerSecond
        )
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

        if let target = frameTarget, target.width > 0, target.height > 0 {
            parts.append(Self.fitFilter(for: target, forceEven: forceEvenDimensionsAndYUV420P))
        }

        if let fps = framesPerSecond, fps > 0 {
            parts.append("fps=\(formatted(fps))")
        }

        if forceEvenDimensionsAndYUV420P {
            parts.append("format=yuv420p")
        }

        return parts.isEmpty ? nil : parts.joined(separator: ",")
    }

    /// Filter chain that lands the frame on exactly `target`'s size.
    /// H.264 (`forceEven`) needs even dimensions throughout, so the target
    /// is rounded down to even and the intermediate scale is forced
    /// divisible by 2 (`force_divisible_by`, ffmpeg >= 4.4).
    static func fitFilter(for target: FrameTarget, forceEven: Bool) -> String {
        let width = forceEven ? max(2, target.width - target.width % 2) : target.width
        let height = forceEven ? max(2, target.height - target.height % 2) : target.height
        let divisible = forceEven ? ":force_divisible_by=2" : ""
        switch target.fitMode {
        case .pad:
            return "scale=\(width):\(height):force_original_aspect_ratio=decrease\(divisible),"
                + "pad=\(width):\(height):(ow-iw)/2:(oh-ih)/2:color=black,setsar=1"
        case .crop:
            return "scale=\(width):\(height):force_original_aspect_ratio=increase\(divisible),"
                + "crop=\(width):\(height),setsar=1"
        case .stretch:
            return "scale=\(width):\(height),setsar=1"
        }
    }

    private func formatted(_ value: Double) -> String {
        // Matches the C# "#.##" invariant-culture formatting (up to 2 decimals, no trailing zeros).
        let rounded = (value * 100).rounded() / 100
        return rounded.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(rounded))
            : String(rounded)
    }
}
