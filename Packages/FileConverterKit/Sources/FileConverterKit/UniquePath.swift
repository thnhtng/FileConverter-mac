import Foundation

/// Ported from PathHelpers.GenerateUniquePath — if `base` already exists on
/// disk, append " (n)" before the extension until a free path is found.
public enum UniquePath {
    public static func generate(base: URL) -> URL {
        guard FileManager.default.fileExists(atPath: base.path) else { return base }

        let directory = base.deletingLastPathComponent()
        let ext = base.pathExtension
        let stem = base.deletingPathExtension().lastPathComponent

        var index = 1
        while true {
            let candidateName = ext.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }
}
