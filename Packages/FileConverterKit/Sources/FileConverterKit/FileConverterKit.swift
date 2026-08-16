// FileConverterKit
//
// Platform-agnostic conversion engine for File Converter on macOS.
// Ported domain knowledge (formats, quality formulas, job lifecycle) from the
// Windows app's Application/FileConverter/ConversionJobs and ConversionPreset
// sources — see /macOS/FileConverterMac/README.md for the porting notes.
//
// This file is a placeholder scaffold; real types land in Phase 1.

public enum FileConverterKit {
    /// Bumped whenever the on-disk settings/preset schema changes.
    public static let settingsSchemaVersion = 1
}
