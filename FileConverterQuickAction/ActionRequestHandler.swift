import Foundation
import AppKit

/// Principal class for the Finder Quick Action (Action Extension).
///
/// Sandbox spike (Phase 0): App/Action extensions are required by the
/// extension-point architecture to run inside the App Sandbox regardless of
/// Developer ID vs. Mac App Store distribution — this handler therefore does
/// **not** shell out to ffmpeg/ImageMagick itself. It only collects the
/// selected file URLs, writes them to a temp list file, and hands off to the
/// unsandboxed main app via a custom URL scheme — the same shape as the
/// Windows shell extension's argv/temp-file hand-off
/// (FileConverterExtension.cs `ConvertFiles`/`--input-files`).
///
/// Note (Phase 3): unlike the Windows shell extension, this hands off with
/// no preset name — a macOS Action Extension is one static menu entry
/// (`NSExtensionServiceMenuItemTitle` in Info.plist), not a dynamically
/// built submenu of every compatible preset, so there's nothing here to
/// pick from ahead of time. The main app resolves the preset instead
/// (auto-picks if exactly one preset is compatible with the selection,
/// otherwise shows a picker) — see `AppModel.handle(request:)`.
final class ActionRequestHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let inputItems = context.inputItems.compactMap { $0 as? NSExtensionItem }
        let providers = inputItems.flatMap { $0.attachments ?? [] }

        let group = DispatchGroup()
        var fileURLs: [URL] = []
        let lock = NSLock()

        for provider in providers where provider.hasItemConformingToTypeIdentifier("public.file-url") {
            group.enter()
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                defer { group.leave() }
                guard let url = Self.fileURL(from: item) else { return }
                lock.lock()
                fileURLs.append(url)
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            Self.handOff(fileURLs: fileURLs)
            context.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    private static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        return nil
    }

    private static func handOff(fileURLs: [URL]) {
        guard !fileURLs.isEmpty else { return }

        let listFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("file-converter-input-\(UUID().uuidString).txt")
        let listContents = fileURLs.map(\.path).joined(separator: "\n")
        try? listContents.write(to: listFile, atomically: true, encoding: .utf8)

        var components = URLComponents()
        components.scheme = "fileconverter"
        components.host = "convert"
        components.queryItems = [
            URLQueryItem(name: "list", value: listFile.path)
        ]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }
}
