import Foundation

public enum MediaProbeError: Error, LocalizedError, Equatable {
    case fileNotFound(String)
    case unreadableProbeOutput

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path): return "File not found: \(path)"
        case .unreadableProbeOutput: return "Couldn't read the file's media information."
        }
    }
}

/// Reads `MediaInfo` for a file: ffprobe for audio/video/most images,
/// `magick identify` as the image fallback (HEIC, PSD, raw...), and plain
/// file attributes for documents.
public enum MediaProbe {
    public static func probe(_ url: URL) async throws -> MediaInfo {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw MediaProbeError.fileNotFound(url.path)
        }
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let category = InputCategoryClassifier.category(forExtension: url.pathExtension)

        if category == .document {
            return MediaInfo(fileURL: url, fileSizeBytes: size, kind: .document)
        }

        if let ffprobe = BinaryLocator.locate(.ffprobe),
           let json = try? await ProcessOutputCapture.stdout(executable: ffprobe, arguments: [
               "-v", "error", "-show_format", "-show_streams", "-of", "json", url.path
           ]),
           let info = try? parse(ffprobeJSON: Data(json.utf8), fileURL: url, fileSizeBytes: size),
           info.kind != .other || category == .misc {
            return info
        }

        if category == .image || category == .animatedImage,
           let magick = BinaryLocator.locate(.magick),
           let output = try? await ProcessOutputCapture.stdout(executable: magick, arguments: [
               "identify", "-format", "%w %h\n", url.path + "[0]"
           ]),
           let dimensions = parseIdentify(output) {
            return MediaInfo(fileURL: url, fileSizeBytes: size, kind: .image, width: dimensions.width, height: dimensions.height)
        }

        let fallbackKind: MediaKind
        switch category {
        case .audio: fallbackKind = .audio
        case .video, .animatedImage: fallbackKind = .video
        case .image: fallbackKind = .image
        case .document: fallbackKind = .document
        case .misc: fallbackKind = .other
        }
        return MediaInfo(fileURL: url, fileSizeBytes: size, kind: fallbackKind)
    }

    // MARK: - Parsing (pure, unit-tested)

    private struct FFprobeOutput: Decodable {
        var streams: [Stream]?
        var format: Format?

        struct Stream: Decodable {
            var codec_type: String?
            var codec_name: String?
            var width: Int?
            var height: Int?
            var avg_frame_rate: String?
            var r_frame_rate: String?
            var duration: String?
            var nb_frames: String?
            var tags: [String: String]?
            var side_data_list: [SideData]?
            var disposition: [String: Int]?
        }

        struct SideData: Decodable {
            var rotation: Double?
        }

        struct Format: Decodable {
            var format_name: String?
            var duration: String?
            var bit_rate: String?
        }
    }

    /// Turns `ffprobe -show_format -show_streams -of json` output into a
    /// `MediaInfo`. Cover-art "video" streams in audio files
    /// (`disposition.attached_pic`) are ignored.
    public static func parse(ffprobeJSON data: Data, fileURL: URL, fileSizeBytes: Int64) throws -> MediaInfo {
        guard let output = try? JSONDecoder().decode(FFprobeOutput.self, from: data) else {
            throw MediaProbeError.unreadableProbeOutput
        }
        let streams = output.streams ?? []
        let video = streams.first { $0.codec_type == "video" && ($0.disposition?["attached_pic"] ?? 0) == 0 }
        let audio = streams.first { $0.codec_type == "audio" }

        let category = InputCategoryClassifier.category(forExtension: fileURL.pathExtension)
        let formatName = output.format?.format_name
        let isStillImageContainer = formatName.map { $0.hasSuffix("_pipe") || $0 == "image2" } ?? false

        let kind: MediaKind
        switch category {
        case .image:
            kind = .image
        case .animatedImage:
            // A GIF is checked like a video (duration, fps) when animated.
            let frames = Int(video?.nb_frames ?? "") ?? 0
            kind = frames > 1 || (Double(output.format?.duration ?? "") ?? 0) > 0 ? .video : .image
        case .audio:
            kind = .audio
        case .video:
            kind = .video
        case .document:
            kind = .document
        case .misc:
            if video != nil {
                kind = isStillImageContainer ? .image : .video
            } else if audio != nil {
                kind = .audio
            } else {
                kind = .other
            }
        }

        let duration = kind == .image ? nil : (Double(output.format?.duration ?? "") ?? Double(video?.duration ?? ""))
        let fps = kind == .video ? (frameRate(video?.avg_frame_rate) ?? frameRate(video?.r_frame_rate)) : nil
        let bitrate = Int(output.format?.bit_rate ?? "").map { $0 / 1000 }

        return MediaInfo(
            fileURL: fileURL,
            fileSizeBytes: fileSizeBytes,
            kind: kind,
            containerFormat: formatName,
            width: video?.width,
            height: video?.height,
            rotationDegrees: rotation(of: video),
            durationSeconds: duration,
            framesPerSecond: fps,
            videoCodec: kind == .video ? video?.codec_name : nil,
            audioCodec: audio?.codec_name,
            hasAudio: audio != nil,
            bitrateKbps: kind == .image ? nil : bitrate
        )
    }

    /// "30000/1001" -> 29.97; "0/0" -> nil.
    static func frameRate(_ fraction: String?) -> Double? {
        guard let fraction else { return nil }
        let parts = fraction.split(separator: "/").compactMap { Double($0) }
        if parts.count == 2 {
            guard parts[1] != 0, parts[0] > 0 else { return nil }
            return parts[0] / parts[1]
        }
        if parts.count == 1, parts[0] > 0 { return parts[0] }
        return nil
    }

    private static func rotation(of stream: FFprobeOutput.Stream?) -> Int {
        guard let stream else { return 0 }
        let fromSideData: Double? = stream.side_data_list?.compactMap { $0.rotation }.first
        let fromTag: Double? = stream.tags?["rotate"].flatMap { Double($0) }
        let raw: Double = fromSideData ?? fromTag ?? 0
        let normalized = ((Int(raw.rounded()) % 360) + 360) % 360
        return [0, 90, 180, 270].contains(normalized) ? normalized : 0
    }

    /// `magick identify -format "%w %h\n"` -> (w, h).
    static func parseIdentify(_ output: String) -> (width: Int, height: Int)? {
        let numbers = output.split(whereSeparator: { $0 == " " || $0.isNewline }).compactMap { Int($0) }
        guard numbers.count >= 2, numbers[0] > 0, numbers[1] > 0 else { return nil }
        return (width: numbers[0], height: numbers[1])
    }
}
