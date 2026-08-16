/// Wraps the per-output-family settings struct relevant to a given
/// `ConversionPreset`. Replaces the Windows app's single flat
/// `Dictionary<string,string>` — see the "Design implication for macOS" note
/// in the plan's Phase 1 exploration.
public enum FormatSettings: Codable, Equatable, Sendable {
    case audio(AudioSettings)
    case video(VideoSettings)
    case gif(GifSettings)
    case image(ImageSettings)
    case document(DocumentSettings)

    public var audio: AudioSettings? {
        if case .audio(let s) = self { return s }
        return nil
    }

    public var video: VideoSettings? {
        if case .video(let s) = self { return s }
        return nil
    }

    public var gifSettings: GifSettings? {
        if case .gif(let s) = self { return s }
        return nil
    }

    public var image: ImageSettings? {
        if case .image(let s) = self { return s }
        return nil
    }

    public var document: DocumentSettings? {
        if case .document(let s) = self { return s }
        return nil
    }
}
