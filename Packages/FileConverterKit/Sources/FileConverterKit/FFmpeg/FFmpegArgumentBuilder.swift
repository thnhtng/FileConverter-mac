import Foundation

public enum FFmpegArgumentBuilderError: Error, Equatable {
    case unsupportedOutputType(OutputType)
    case unrecognizedBitrate(Int)
    case missingSettings
}

/// Pure argument-list builder — no process execution, fully unit-testable.
/// Ported from `FillFFMpegArgumentsList` + the encoder-arg switch in
/// ConversionJob_FFMPEG.cs:89-426. Two deliberate deviations from the
/// Windows app (see the plan's Phase 1 notes):
///  1. Arguments are built as `[String]` arrays, not a single shell string
///     (no quoting bugs, and `Process` wants argv anyway).
///  2. Progress is read from `-progress pipe:1` on **stdout**
///     (`FFmpegProgress`), not regex-scraped from stderr.
public enum FFmpegArgumentBuilder {
    private static let baseArgs = ["-n", "-progress", "pipe:1"]
    private static let mp3MetadataArgs = ["-id3v2_version", "3", "-write_id3v1", "1"]
    private static let aacMetadataArgs = ["-write_apetag", "1"]

    public static func passes(for preset: ConversionPreset, inputURL: URL, outputURL: URL) throws -> [FFmpegPass] {
        let input = inputURL.path
        let output = outputURL.path

        switch preset.outputType {
        case .aac:
            guard case .audio(let s)? = preset.settings as FormatSettings? else { throw FFmpegArgumentBuilderError.missingSettings }
            guard let qIndex = FFmpegQualityFormulas.aacQualityIndex(bitrateKbps: s.bitrateKbps) else {
                throw FFmpegArgumentBuilderError.unrecognizedBitrate(s.bitrateKbps)
            }
            var args = baseArgs + ["-i", input, "-c:a", "aac", "-q:a", qIndex]
            args += channelArgs(s.channelCount)
            args += aacMetadataArgs
            args.append(output)
            return [FFmpegPass(arguments: args)]

        case .avi:
            guard let video = preset.settings.video else { throw FFmpegArgumentBuilderError.missingSettings }
            let transform = FFmpegTransform(scale: video.scale, rotationDegrees: video.rotationDegrees)
            var args = baseArgs + ["-i", input, "-c:v", "mpeg4", "-vtag", "xvid",
                                    "-qscale:v", "\(FFmpegQualityFormulas.mpeg4QualityIndex(quality: video.quality))"]
            if video.enableAudio {
                guard let mp3Index = FFmpegQualityFormulas.mp3VBRQualityIndex(bitrateKbps: video.audioBitrateKbps) else {
                    throw FFmpegArgumentBuilderError.unrecognizedBitrate(video.audioBitrateKbps)
                }
                args += ["-c:a", "libmp3lame", "-qscale:a", "\(mp3Index)"]
            } else {
                args.append("-an")
            }
            if let filter = transform.filterGraph() { args += ["-vf", filter] }
            args += mp3MetadataArgs
            args.append(output)
            return [FFmpegPass(arguments: args)]

        case .flac:
            guard case .audio(let s)? = preset.settings as FormatSettings? else { throw FFmpegArgumentBuilderError.missingSettings }
            var args = baseArgs + ["-i", input, "-compression_level", "12"]
            args += channelArgs(s.channelCount)
            args.append(output)
            return [FFmpegPass(arguments: args)]

        case .gif:
            guard let gif = preset.settings.gifSettings else { throw FFmpegArgumentBuilderError.missingSettings }
            let transform = FFmpegTransform(scale: gif.scale, rotationDegrees: gif.rotationDegrees)
            var filterBase = transform.filterGraph() ?? ""
            filterBase += (filterBase.isEmpty ? "" : ",") + "fps=\(gif.framesPerSecond)"

            let paletteURL = UniquePath.generate(
                base: FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(inputURL.lastPathComponent) - palette.png")
            )

            let paletteArgs = baseArgs + ["-i", input, "-vf", "\(filterBase),palettegen", paletteURL.path]
            let gifArgs = baseArgs + ["-i", input, "-i", paletteURL.path, "-lavfi", "\(filterBase),paletteuse", output]

            return [
                FFmpegPass(name: "Indexing colors", arguments: paletteArgs, fileToDelete: paletteURL),
                FFmpegPass(name: "Encoding", arguments: gifArgs)
            ]

        case .mp3:
            guard case .audio(let s)? = preset.settings as FormatSettings? else { throw FFmpegArgumentBuilderError.missingSettings }
            var args = baseArgs + ["-i", input, "-codec:a", "libmp3lame"]
            switch s.encodingMode {
            case .mp3VBR:
                guard let idx = FFmpegQualityFormulas.mp3VBRQualityIndex(bitrateKbps: s.bitrateKbps) else {
                    throw FFmpegArgumentBuilderError.unrecognizedBitrate(s.bitrateKbps)
                }
                args += ["-q:a", "\(idx)"]
            case .mp3CBR:
                args += ["-b:a", "\(s.bitrateKbps)k"]
            default:
                break
            }
            args += channelArgs(s.channelCount)
            args += mp3MetadataArgs
            args.append(output)
            return [FFmpegPass(arguments: args)]

        case .mkv, .mp4:
            guard let video = preset.settings.video else { throw FFmpegArgumentBuilderError.missingSettings }
            let transform = FFmpegTransform(scale: video.scale, rotationDegrees: video.rotationDegrees, forceEvenDimensionsAndYUV420P: true)
            var args = baseArgs + ["-i", input,
                                    "-c:v", "libx264",
                                    "-preset", FFmpegQualityFormulas.h264Preset(video.encodingSpeed),
                                    "-crf", "\(FFmpegQualityFormulas.h264CRF(quality: video.quality))"]
            if video.enableAudio {
                guard let aacIndex = FFmpegQualityFormulas.aacQualityIndex(bitrateKbps: video.audioBitrateKbps) else {
                    throw FFmpegArgumentBuilderError.unrecognizedBitrate(video.audioBitrateKbps)
                }
                args += ["-c:a", "aac", "-qscale:a", aacIndex]
            } else {
                args.append("-an")
            }
            if let filter = transform.filterGraph() { args += ["-vf", filter] }
            args.append(output)
            return [FFmpegPass(arguments: args)]

        case .ogg:
            guard case .audio(let s)? = preset.settings as FormatSettings? else { throw FFmpegArgumentBuilderError.missingSettings }
            guard let idx = FFmpegQualityFormulas.oggVBRQualityIndex(bitrateKbps: s.bitrateKbps) else {
                throw FFmpegArgumentBuilderError.unrecognizedBitrate(s.bitrateKbps)
            }
            var args = baseArgs + ["-i", input, "-vn", "-codec:a", "libvorbis", "-qscale:a", "\(idx)"]
            args += channelArgs(s.channelCount)
            args.append(output)
            return [FFmpegPass(arguments: args)]

        case .ogv:
            guard let video = preset.settings.video else { throw FFmpegArgumentBuilderError.missingSettings }
            let transform = FFmpegTransform(scale: video.scale, rotationDegrees: video.rotationDegrees)
            var args = baseArgs + ["-i", input, "-codec:v", "libtheora",
                                    "-qscale:v", "\(FFmpegQualityFormulas.theoraQualityIndex(quality: video.quality))"]
            if video.enableAudio {
                guard let idx = FFmpegQualityFormulas.oggVBRQualityIndex(bitrateKbps: video.audioBitrateKbps) else {
                    throw FFmpegArgumentBuilderError.unrecognizedBitrate(video.audioBitrateKbps)
                }
                args += ["-codec:a", "libvorbis", "-qscale:a", "\(idx)"]
            } else {
                args.append("-an")
            }
            if let filter = transform.filterGraph() { args += ["-vf", filter] }
            args.append(output)
            return [FFmpegPass(arguments: args)]

        case .wav:
            guard case .audio(let s)? = preset.settings as FormatSettings? else { throw FFmpegArgumentBuilderError.missingSettings }
            var args = baseArgs + ["-i", input, "-acodec", FFmpegQualityFormulas.wavCodecArgument(s.encodingMode)]
            args += channelArgs(s.channelCount)
            args.append(output)
            return [FFmpegPass(arguments: args)]

        case .webm:
            guard let video = preset.settings.video else { throw FFmpegArgumentBuilderError.missingSettings }
            let transform = FFmpegTransform(scale: video.scale, rotationDegrees: video.rotationDegrees)
            var args = baseArgs + ["-i", input, "-c:v", "libvpx-vp9"]
            if video.quality == 63 {
                args += ["-lossless", "1"]
            } else {
                args += ["-crf", "\(FFmpegQualityFormulas.webmCRF(quality: video.quality))", "-b:v", "0"]
            }
            if video.enableAudio {
                guard let idx = FFmpegQualityFormulas.oggVBRQualityIndex(bitrateKbps: video.audioBitrateKbps) else {
                    throw FFmpegArgumentBuilderError.unrecognizedBitrate(video.audioBitrateKbps)
                }
                args += ["-c:a", "libvorbis", "-qscale:a", "\(idx)"]
            } else {
                args.append("-an")
            }
            if let filter = transform.filterGraph() { args += ["-vf", filter] }
            args.append(output)
            return [FFmpegPass(arguments: args)]

        case .ico:
            // Remux only — used by IcoConversionJob on an already-prepared
            // PNG. No encoder args, matches ConversionJob_FFMPEG.cs:196-204.
            return [FFmpegPass(arguments: baseArgs + ["-i", input, output])]

        case .avif, .jpg, .pdf, .png, .webp:
            // Routed to the ImageMagick backend instead (ConversionJobFactory.cs
            // dispatch: Pdf|Avif|Jpg|Png|Webp -> ConversionJob_ImageMagick).
            throw FFmpegArgumentBuilderError.unsupportedOutputType(preset.outputType)
        }
    }

    private static func channelArgs(_ channelCount: Int) -> [String] {
        channelCount > 0 ? ["-ac", "\(channelCount)"] : []
    }
}
