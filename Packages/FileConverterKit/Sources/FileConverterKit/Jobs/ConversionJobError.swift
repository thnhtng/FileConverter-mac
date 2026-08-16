import Foundation

public enum ConversionJobError: Error, LocalizedError {
    case binaryNotFound(String)
    case libreOfficeNotInstalled
    case outputFileMissing(URL)
    case unsupportedPipeline(String)

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound(let name):
            return "Can't find \(name). Try reinstalling File Converter."
        case .libreOfficeNotInstalled:
            return "LibreOffice is required to convert Office documents. Install it from libreoffice.org, then try again."
        case .outputFileMissing(let url):
            return "Conversion reported success but \(url.lastPathComponent) is missing."
        case .unsupportedPipeline(let detail):
            return "Unsupported conversion: \(detail)"
        }
    }
}

/// Progress in [0, 1]. Reported frequently during a conversion.
public typealias ConversionProgressHandler = @Sendable (Double) -> Void
