/// Ported from InputPostConversionAction.cs.
public enum InputPostConversionAction: String, Codable, Sendable {
    case none
    case moveInArchiveFolder
    case delete
}

/// Ported from ConversionState.cs.
public enum ConversionState: String, Sendable {
    case unknown
    case ready
    case inProgress
    case done
    case failed
}
