import Foundation

/// User-facing knobs for automatic fixes.
public struct SpecFixOptions: Equatable, Sendable {
    /// How to reach a different frame size/ratio. `.pad` never loses
    /// content, so it's the default; `.crop` fills the frame.
    public var fitMode: FrameFitMode

    public init(fitMode: FrameFitMode = .pad) {
        self.fitMode = fitMode
    }
}

/// A ready-to-run conversion that should make a file pass its spec, plus a
/// plain-language list of what it will change (shown before running).
public struct SpecFixPlan: Equatable, Sendable {
    public var preset: ConversionPreset
    public var actions: [String]
}

public enum SpecFixUnavailableReason: Error, Equatable, LocalizedError, Sendable {
    case nothingToFix
    case wrongMediaKind(expected: [MediaKind], actual: MediaKind)
    case unsupportedMediaKind(MediaKind)
    case tooShort(actualSeconds: Double, minimumSeconds: Double)
    case noSupportedOutputFormat(allowed: [String])
    case sizeLimitTooSmall(maxMB: Double, durationSeconds: Double)
    case missingMediaInfo(String)

    public var errorDescription: String? {
        switch self {
        case .nothingToFix:
            return "This file already meets the spec."
        case .wrongMediaKind(let expected, let actual):
            return "The spec is for \(expected.map(\.rawValue).joined(separator: "/")) files, but this is \(actual.rawValue). Pick another file or spec."
        case .unsupportedMediaKind(let kind):
            return "Automatic fixes aren't available for \(kind.rawValue) files yet — fix it manually."
        case .tooShort(let actual, let minimum):
            return "The video is \(SpecFormat.seconds(actual)) but the spec needs at least \(SpecFormat.seconds(minimum)). That needs a re-edit, not a conversion."
        case .noSupportedOutputFormat(let allowed):
            return "File Converter can't produce any of the allowed formats (\(allowed.joined(separator: ", "))). Export from your editor instead."
        case .sizeLimitTooSmall(let maxMB, let duration):
            return "\(SpecFormat.megabytes(maxMB)) is too small for \(SpecFormat.seconds(duration)) of video at watchable quality. Shorten the video or ask for a higher limit."
        case .missingMediaInfo(let what):
            return "Couldn't read the file's \(what), so a fix can't be planned. Is it a valid media file?"
        }
    }
}

/// Turns a failing `SpecCheckResult` into a `ConversionPreset` that targets
/// the spec. Pure (no I/O): the UI shows `actions`, runs the preset through
/// the normal `ConversionQueue`, then re-checks the output — the plan is a
/// best effort (e.g. a bitrate cap is aimed with headroom, not guaranteed),
/// and the re-check is what proves it.
public enum SpecFixPlanner {
    /// Share of the size limit the encode aims for — headroom for container
    /// overhead and VBV overshoot.
    static let sizeHeadroom = 0.9
    static let defaultAudioKbps = 128
    static let reducedAudioKbps = 64
    static let minimumVideoKbps = 150

    public static func plan(
        for result: SpecCheckResult,
        spec: DeliverySpec,
        options: SpecFixOptions = SpecFixOptions()
    ) -> Result<SpecFixPlan, SpecFixUnavailableReason> {
        let failed = Set(result.failures.map(\.rule))
        guard !failed.isEmpty else { return .failure(.nothingToFix) }
        if failed.contains(.mediaKind) {
            return .failure(.wrongMediaKind(expected: spec.mediaKinds, actual: result.info.kind))
        }

        switch result.info.kind {
        case .video:
            return planVideo(info: result.info, spec: spec, failed: failed, options: options)
        case .image:
            return planImage(info: result.info, spec: spec, failed: failed, options: options)
        case .audio, .document, .other:
            return .failure(.unsupportedMediaKind(result.info.kind))
        }
    }

    // MARK: - Video

    private struct VideoTarget {
        let outputType: OutputType
        let videoCodec: String
        let audioCodec: String
    }

    private static let videoTargets = [
        VideoTarget(outputType: .mp4, videoCodec: "h264", audioCodec: "aac"),
        VideoTarget(outputType: .mkv, videoCodec: "h264", audioCodec: "aac"),
        VideoTarget(outputType: .webm, videoCodec: "vp9", audioCodec: "vorbis")
    ]

    private static func planVideo(
        info: MediaInfo,
        spec: DeliverySpec,
        failed: Set<SpecRule>,
        options: SpecFixOptions
    ) -> Result<SpecFixPlan, SpecFixUnavailableReason> {
        if failed.contains(.duration), let minimum = spec.minDurationSeconds,
           let actual = info.durationSeconds, actual < minimum {
            return .failure(.tooShort(actualSeconds: actual, minimumSeconds: minimum))
        }

        let willHaveAudio = spec.audio == .required || (spec.audio == .optional && info.hasAudio)
        let allowedExts = (spec.allowedExtensions ?? []).filter { !$0.isEmpty }
        guard let target = videoTargets.first(where: { target in
            allows(allowedExts, target.outputType.rawValue)
                && allows(spec.allowedVideoCodecs, target.videoCodec)
                && (!willHaveAudio || allows(spec.allowedAudioCodecs, target.audioCodec))
        }) else {
            return .failure(.noSupportedOutputFormat(allowed: allowedExts))
        }

        guard var video = DefaultPresets.defaultSettings(for: target.outputType).video else {
            return .failure(.noSupportedOutputFormat(allowed: allowedExts))
        }
        var actions: [String] = []
        if target.outputType.rawValue != DeliverySpec.normalizedExtension(info.fileExtension)
            || info.videoCodec?.lowercased() != target.videoCodec {
            actions.append("Re-encode as .\(target.outputType.rawValue) (\(target.videoCodec.uppercased()))")
        } else {
            actions.append("Re-encode (\(target.videoCodec.uppercased()))")
        }

        // Frame size / aspect ratio
        if !failed.isDisjoint(with: [.dimensions, .aspectRatio]) {
            guard let size = targetFrameSize(info: info, spec: spec, fitMode: options.fitMode, evenDimensions: true) else {
                return .failure(.missingMediaInfo("dimensions"))
            }
            video.frameTarget = FrameTarget(width: size.width, height: size.height, fitMode: options.fitMode)
            actions.append(describeResize(to: size, fitMode: options.fitMode, ratioChanges: failed.contains(.aspectRatio) || ratioDiffers(info, size)))
        }

        // Duration
        var outputDuration = info.durationSeconds
        if failed.contains(.duration), let maximum = spec.maxDurationSeconds {
            video.maxDurationSeconds = maximum
            outputDuration = min(outputDuration ?? maximum, maximum)
            actions.append("Trim to the first \(SpecFormat.seconds(maximum))")
        }

        // Frame rate
        if failed.contains(.frameRate), let fps = info.framesPerSecond {
            if let maximum = spec.maxFramesPerSecond, fps > maximum {
                video.framesPerSecond = maximum
                actions.append("Lower frame rate to \(SpecFormat.fps(maximum))")
            } else if let minimum = spec.minFramesPerSecond, fps < minimum {
                video.framesPerSecond = minimum
                actions.append("Raise frame rate to \(SpecFormat.fps(minimum))")
            }
        }

        // Audio track
        switch spec.audio {
        case .required:
            video.enableAudio = true
            if !info.hasAudio {
                video.addSilentAudioIfMissing = true
                actions.append("Add a silent audio track")
            }
        case .forbidden:
            video.enableAudio = false
            if info.hasAudio { actions.append("Remove the audio track") }
        case .optional:
            video.enableAudio = info.hasAudio
        }
        video.audioBitrateKbps = defaultAudioKbps

        // File size: aim the bitrate at the limit.
        if let maxMB = spec.maxFileSizeMB {
            guard let duration = outputDuration, duration > 0 else {
                if failed.contains(.fileSize) { return .failure(.missingMediaInfo("duration")) }
                return .success(makePlan(info: info, spec: spec, outputType: target.outputType, settings: .video(video), actions: actions))
            }
            let totalKbps = maxMB * 8000 * sizeHeadroom / duration
            var audioKbps = video.enableAudio ? defaultAudioKbps : 0
            if video.enableAudio && totalKbps - Double(audioKbps) < Double(minimumVideoKbps) * 2 {
                audioKbps = reducedAudioKbps
            }
            let videoKbps = Int(totalKbps) - audioKbps
            guard videoKbps >= minimumVideoKbps else {
                return .failure(.sizeLimitTooSmall(maxMB: maxMB, durationSeconds: duration))
            }
            video.audioBitrateKbps = max(audioKbps, reducedAudioKbps)
            video.maxVideoBitrateKbps = videoKbps
            if failed.contains(.fileSize) {
                actions.append("Cap bitrate at \(videoKbps) kbps to fit \(SpecFormat.megabytes(maxMB))")
            }
        }

        return .success(makePlan(info: info, spec: spec, outputType: target.outputType, settings: .video(video), actions: actions))
    }

    // MARK: - Image

    private static let imageOutputTypes: [OutputType] = [.png, .jpg, .webp, .avif]

    private static func planImage(
        info: MediaInfo,
        spec: DeliverySpec,
        failed: Set<SpecRule>,
        options: SpecFixOptions
    ) -> Result<SpecFixPlan, SpecFixUnavailableReason> {
        let allowedExts = (spec.allowedExtensions ?? []).filter { !$0.isEmpty }
        let isAllowed: (OutputType) -> Bool = { allowedExts.isEmpty || allowedExts.contains($0.rawValue) }
        let sourceType = imageOutputTypes.first { $0.rawValue == DeliverySpec.normalizedExtension(info.fileExtension) }

        var outputType: OutputType
        if let sourceType, isAllowed(sourceType) {
            outputType = sourceType
        } else if let first = imageOutputTypes.first(where: isAllowed) {
            outputType = first
        } else {
            return .failure(.noSupportedOutputFormat(allowed: allowedExts))
        }

        // Lossless PNG rarely shrinks enough; switch to JPG when allowed.
        if failed.contains(.fileSize), outputType == .png, isAllowed(.jpg) {
            outputType = .jpg
        }

        guard var image = DefaultPresets.defaultSettings(for: outputType).image else {
            return .failure(.noSupportedOutputFormat(allowed: allowedExts))
        }

        var actions: [String] = []
        if outputType != sourceType {
            actions.append("Convert to .\(outputType.rawValue)")
        }

        if !failed.isDisjoint(with: [.dimensions, .aspectRatio]) {
            guard let size = targetFrameSize(info: info, spec: spec, fitMode: options.fitMode, evenDimensions: false) else {
                return .failure(.missingMediaInfo("dimensions"))
            }
            image.frameTarget = FrameTarget(width: size.width, height: size.height, fitMode: options.fitMode)
            actions.append(describeResize(to: size, fitMode: options.fitMode, ratioChanges: failed.contains(.aspectRatio) || ratioDiffers(info, size)))
        }

        if failed.contains(.fileSize) {
            if outputType == .png {
                actions.append("Re-save as PNG (may still be too large — PNG is lossless)")
            } else {
                image.quality = min(image.quality, 80)
                actions.append("Lower quality to \(image.quality) to reduce size")
            }
        }

        if actions.isEmpty {
            actions.append("Re-save as .\(outputType.rawValue)")
        }

        return .success(makePlan(info: info, spec: spec, outputType: outputType, settings: .image(image), actions: actions))
    }

    // MARK: - Shared

    /// nil/empty allow-list = anything goes.
    private static func allows(_ list: [String]?, _ value: String) -> Bool {
        guard let list, !list.isEmpty else { return true }
        return list.contains(value)
    }

    private static func makePlan(
        info: MediaInfo,
        spec: DeliverySpec,
        outputType: OutputType,
        settings: FormatSettings,
        actions: [String]
    ) -> SpecFixPlan {
        let preset = ConversionPreset(
            fullName: "Spec Fix/\(spec.name)",
            outputType: outputType,
            inputTypes: [info.fileExtension],
            inputPostConversionAction: .none,
            outputFileNameTemplate: "(p)(f)_fixed",
            settings: settings,
            isDefaultSettings: false
        )
        return SpecFixPlan(preset: preset, actions: actions)
    }

    private static func ratioDiffers(_ info: MediaInfo, _ size: (width: Int, height: Int)) -> Bool {
        guard let w = info.displayWidth, let h = info.displayHeight, w > 0, h > 0, size.height > 0 else { return false }
        let source = Double(w) / Double(h)
        let target = Double(size.width) / Double(size.height)
        return abs(source - target) > target * 0.01
    }

    private static func describeResize(to size: (width: Int, height: Int), fitMode: FrameFitMode, ratioChanges: Bool) -> String {
        guard ratioChanges else { return "Resize to \(size.width) × \(size.height)" }
        switch fitMode {
        case .pad: return "Resize to \(size.width) × \(size.height), adding black bars (nothing is cut off)"
        case .crop: return "Resize to \(size.width) × \(size.height), cropping the edges to fill the frame"
        case .stretch: return "Stretch to \(size.width) × \(size.height)"
        }
    }

    /// The frame size a fix should produce.
    ///  1. Exact width+height in the spec -> that.
    ///  2. One exact side -> that side, other side keeps the source ratio
    ///     (or the spec's first allowed ratio, if the source ratio fails).
    ///  3. Otherwise start from the source size, change its ratio to the
    ///     spec's first allowed ratio if needed (growing for pad, shrinking
    ///     for crop, so no source pixels are scaled down unnecessarily), then
    ///     scale uniformly into the min/max bounds.
    static func targetFrameSize(
        info: MediaInfo,
        spec: DeliverySpec,
        fitMode: FrameFitMode,
        evenDimensions: Bool
    ) -> (width: Int, height: Int)? {
        func finish(_ w: Double, _ h: Double) -> (width: Int, height: Int) {
            var width = max(1, Int(w.rounded()))
            var height = max(1, Int(h.rounded()))
            if evenDimensions {
                width = max(2, width - width % 2)
                height = max(2, height - height % 2)
            }
            return (width, height)
        }

        if let w = spec.width, let h = spec.height { return finish(Double(w), Double(h)) }

        guard let srcW = info.displayWidth, let srcH = info.displayHeight, srcW > 0, srcH > 0 else { return nil }
        let sourceRatio = Double(srcW) / Double(srcH)
        let ratios = spec.aspectRatios ?? []
        let sourceRatioAllowed = ratios.isEmpty
            || ratios.contains { abs(sourceRatio - $0.value) <= $0.value * spec.aspectRatioTolerance }
        let ratio = sourceRatioAllowed ? sourceRatio : ratios[0].value

        if let w = spec.width { return finish(Double(w), Double(w) / ratio) }
        if let h = spec.height { return finish(Double(h) * ratio, Double(h)) }

        var width = Double(srcW)
        var height = Double(srcH)
        if !sourceRatioAllowed {
            let grow = fitMode == .pad
            if (sourceRatio > ratio) == grow {
                // pad + too wide, or crop + too tall: keep width
                height = width / ratio
            } else {
                width = height * ratio
            }
        }

        // Uniform scale into bounds. Max wins over min if they conflict.
        var scale = 1.0
        if let minW = spec.minWidth, width < Double(minW) { scale = max(scale, Double(minW) / width) }
        if let minH = spec.minHeight, height < Double(minH) { scale = max(scale, Double(minH) / height) }
        if let maxW = spec.maxWidth, width * scale > Double(maxW) { scale = Double(maxW) / width }
        if let maxH = spec.maxHeight, height * scale > Double(maxH) { scale = min(scale, Double(maxH) / height) }

        return finish(width * scale, height * scale)
    }
}
