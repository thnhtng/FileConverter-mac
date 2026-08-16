import Foundation

/// Replaces ConversionJob_Office.cs / _Word.cs / _Excel.cs / _PowerPoint.cs
/// (Windows COM automation of desktop Office) with LibreOffice headless
/// conversion — the plan's chosen macOS equivalent. Doc/xls/ppt family ->
/// PDF via `soffice --headless --convert-to pdf`, then (mirroring the
/// Windows doc->PDF->image chain) into ImageMagick if the final output type
/// isn't Pdf.
public struct OfficeConversionExecutor {
    public init() {}

    @discardableResult
    public func execute(
        preset: ConversionPreset,
        inputURL: URL,
        outputURL: URL,
        progress: ConversionProgressHandler? = nil
    ) async throws -> [URL] {
        guard let soffice = BinaryLocator.locate(.soffice) else {
            throw ConversionJobError.libreOfficeNotInstalled
        }

        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let runner = ProcessRunner()
        try await runner.run(executable: soffice, arguments: [
            "--headless", "--norestore",
            "--convert-to", "pdf",
            "--outdir", workDir.path,
            inputURL.path
        ])

        let producedPDF = workDir.appendingPathComponent(
            inputURL.deletingPathExtension().lastPathComponent + ".pdf"
        )
        guard FileManager.default.fileExists(atPath: producedPDF.path) else {
            throw ConversionJobError.outputFileMissing(producedPDF)
        }

        if preset.outputType == .pdf {
            let finalURL = UniquePath.generate(base: outputURL)
            try FileManager.default.moveItem(at: producedPDF, to: finalURL)
            progress?(1)
            return [finalURL]
        }

        // Chain into ImageMagick for the final image format(s), matching the
        // Windows doc -> PDF -> image pipeline.
        return try await ImageMagickConversionExecutor().execute(
            preset: preset, inputURL: producedPDF, outputURL: outputURL
        ) { fraction in progress?(0.5 + fraction * 0.5) }
    }
}
