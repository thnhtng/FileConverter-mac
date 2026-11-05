import Foundation
import FileConverterKit

/// A pending "convert these files with this preset" request, arriving via
/// either the Quick Action's URL scheme hand-off
/// (`fileconverter://convert?preset=<name>&list=<tempPath>`, written by
/// ActionRequestHandler.swift) or plain CLI args for manual/dev launches
/// (`FileConverter <file1> <file2> --preset <name>`). Mirrors the two
/// hand-off paths the Windows shell extension used
/// (`--conversion-preset <name> <files...>` / `--input-files <path>`,
/// FileConverterExtension.cs `ConvertFiles`).
///
/// `mode == .check` (`fileconverter://check?list=...` or `--check`) opens the
/// files in Spec Check instead of converting them.
struct LaunchRequest {
    enum Mode { case convert, check }

    var presetName: String?
    var fileURLs: [URL]
    var mode: Mode = .convert

    static func from(commandLineArguments arguments: [String]) -> LaunchRequest? {
        var presetName: String?
        var files: [URL] = []
        var mode = Mode.convert
        var index = 1 // skip argv[0]
        while index < arguments.count {
            let arg = arguments[index]
            switch arg {
            case "--check":
                mode = .check
            case "--preset":
                index += 1
                if index < arguments.count { presetName = arguments[index] }
            case "--input-files":
                index += 1
                if index < arguments.count {
                    files += Self.readFileList(at: URL(fileURLWithPath: arguments[index]))
                }
            default:
                // Skip flags the system adds to GUI launches (e.g.
                // -NSDocumentRevisionsDebugMode YES from Xcode).
                if arg.hasPrefix("-") {
                    if index + 1 < arguments.count, !arguments[index + 1].hasPrefix("/") { index += 1 }
                } else {
                    files.append(URL(fileURLWithPath: arg))
                }
            }
            index += 1
        }
        guard !files.isEmpty else { return nil }
        return LaunchRequest(presetName: presetName, fileURLs: files, mode: mode)
    }

    static func from(url: URL) -> LaunchRequest? {
        guard url.scheme == "fileconverter", url.host == "convert" || url.host == "check" else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = components?.queryItems ?? []
        let presetName = query.first(where: { $0.name == "preset" })?.value
        guard let listPath = query.first(where: { $0.name == "list" })?.value else { return nil }

        let files = readFileList(at: URL(fileURLWithPath: listPath))
        defer { try? FileManager.default.removeItem(atPath: listPath) }
        guard !files.isEmpty else { return nil }
        return LaunchRequest(presetName: presetName, fileURLs: files, mode: url.host == "check" ? .check : .convert)
    }

    private static func readFileList(at url: URL) -> [URL] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return contents
            .split(separator: "\n")
            .map { URL(fileURLWithPath: $0.trimmingCharacters(in: .whitespaces)) }
    }
}
