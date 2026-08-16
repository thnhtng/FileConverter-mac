import Foundation

/// Ported from ConversionPreset.cs. A preset bundles: which output format,
/// which input extensions it accepts, what to do with the input file after a
/// successful conversion, the output file naming template, and the
/// format-specific settings.
public struct ConversionPreset: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID

    /// May contain "/" separators for submenu grouping in the Quick Action
    /// menu, e.g. "Scale 75%/To Mkv" (ConversionPreset.cs FullName).
    public var fullName: String

    public var outputType: OutputType
    public var inputTypes: [String]
    public var inputPostConversionAction: InputPostConversionAction

    /// Placeholder-token template, e.g. "(p)(f)" or "(p)(f) (n:i) of (n:c)".
    /// See PathHelpers.GenerateFilePathFromTemplate on the Windows side;
    /// tokens: (p) parent path, (f) filename, (n:i)/(n:c) page index/count.
    public var outputFileNameTemplate: String

    public var settings: FormatSettings
    public var isDefaultSettings: Bool

    public init(
        id: UUID = UUID(),
        fullName: String,
        outputType: OutputType,
        inputTypes: [String],
        inputPostConversionAction: InputPostConversionAction = .none,
        outputFileNameTemplate: String = "(p)(f)",
        settings: FormatSettings,
        isDefaultSettings: Bool = true
    ) {
        self.id = id
        self.fullName = fullName
        self.outputType = outputType
        self.inputTypes = inputTypes.map { $0.lowercased() }
        self.inputPostConversionAction = inputPostConversionAction
        self.outputFileNameTemplate = outputFileNameTemplate
        self.settings = settings
        self.isDefaultSettings = isDefaultSettings
    }

    /// The last path component of `fullName`, e.g. "To Mkv" for
    /// "Scale 75%/To Mkv".
    public var shortName: String {
        fullName.split(separator: "/").last.map(String.init) ?? fullName
    }

    /// The "/"-delimited folder path above `shortName`, e.g. ["Scale 75%"].
    public var parentFolderNames: [String] {
        let components = fullName.split(separator: "/").map(String.init)
        return components.isEmpty ? [] : Array(components.dropLast())
    }

    /// Whether this preset accepts the given input file extension (no dot).
    public func accepts(inputExtension: String) -> Bool {
        inputTypes.contains(inputExtension.lowercased())
    }
}
