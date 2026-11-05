import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum SpecImportError: Error, LocalizedError, Equatable {
    case missingAPIKey
    case emptyInput
    case http(status: Int, message: String)
    case refused
    case truncated
    case unreadableResponse

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Add a Claude API key in Settings to use AI import."
        case .emptyInput: return "Paste the spec text first."
        case .http(let status, let message): return "Claude API error (\(status)): \(message)"
        case .refused: return "Claude declined this request. Try pasting only the spec section."
        case .truncated: return "The response was cut off. Try pasting a shorter excerpt."
        case .unreadableResponse: return "Couldn't read a spec from Claude's response."
        }
    }
}

/// "Paste the partner's spec, get a `DeliverySpec`": sends free-form spec
/// text (an email, a PDF excerpt, a help-center page) to the Claude
/// Messages API with a JSON-schema-constrained response, and decodes it.
///
/// The result is a *draft*: the UI always shows it in the spec editor for a
/// person to review before saving — the AI proposes, the human decides.
/// Raw HTTP via URLSession because there's no official Swift SDK.
public struct ClaudeSpecImporter: Sendable {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let apiVersion = "2026-10-21"
    public static let defaultModel = "claude-opus-5-5"
    /// Server-side fallback: if the primary model declines, the API retries
    /// on a suitable fallback model instead of failing the import.
    static let fallbackBeta = "server-side-fallback-2026-07-01"

    public var apiKey: String
    public var model: String

    public init(apiKey: String, model: String = ClaudeSpecImporter.defaultModel) {
        self.apiKey = apiKey
        self.model = model
    }

    public func importSpec(from text: String) async throws -> DeliverySpec {
        let request = try makeURLRequest(text: text)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw SpecImportError.http(status: status, message: Self.errorMessage(from: data))
        }
        return try Self.parseResponse(data)
    }

    // MARK: - Request (pure, unit-tested)

    func makeURLRequest(text: String) throws -> URLRequest {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw SpecImportError.missingAPIKey }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { throw SpecImportError.emptyInput }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(trimmedKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: Self.requestBody(model: model, text: trimmedText), options: [.sortedKeys])
        return request
    }

    static let systemPrompt = """
    You turn media delivery requirements (ad creative specs, app store asset rules, \
    upload limits) into a structured checklist that a file checker will enforce.

    Rules:
    - Only fill a field when the text states it. Use null for anything not stated; \
    never invent typical values.
    - File sizes in decimal megabytes (1 MB = 1,000,000 bytes; convert KB/GB).
    - Durations in seconds. Frame rates in frames per second.
    - Extensions lowercase without the dot ("mp4", "mov", "png", "jpg").
    - Codec names as ffprobe reports them: h264, hevc, vp9, av1, prores, aac, mp3, opus, vorbis.
    - width/height are exact required pixel sizes; use the min/max fields for ranges \
    or "at least" wording.
    - audio: "required" if a sound track is mandatory, "forbidden" if it must be silent, \
    otherwise "optional".
    - If the text describes several placements or sizes, build the spec for the one the \
    user asks about, or else the first one, and list the others briefly in notes.
    - name: short, descriptive. notes: one or two sentences, in the same language as the input.
    """

    static func requestBody(model: String, text: String) -> [String: Any] {
        [
            "model": model,
            "max_tokens": 16000,
            "fallbacks": "default",
            "system": systemPrompt,
            "output_config": [
                "effort": "low",
                "format": ["type": "json_schema", "schema": responseSchema] as [String: Any]
            ] as [String: Any],
            "messages": [
                ["role": "user", "content": "Delivery requirements:\n\n\(text)"]
            ]
        ]
    }

    /// JSON schema for the structured output. Every key is required and
    /// nullable — structured outputs need `additionalProperties: false` and
    /// a full `required` list on every object.
    static var responseSchema: [String: Any] {
        func nullable(_ type: String) -> [String: Any] {
            ["anyOf": [["type": type], ["type": "null"]]]
        }
        func nullableArray(of items: [String: Any]) -> [String: Any] {
            ["anyOf": [["type": "array", "items": items], ["type": "null"]] as [[String: Any]]]
        }
        let ratio: [String: Any] = [
            "type": "object",
            "properties": ["width": ["type": "integer"], "height": ["type": "integer"]],
            "required": ["width", "height"],
            "additionalProperties": false
        ]
        let properties: [String: Any] = [
            "name": ["type": "string"],
            "notes": nullable("string"),
            "mediaKinds": [
                "type": "array",
                "items": ["type": "string", "enum": ["video", "audio", "image", "document"]] as [String: Any]
            ] as [String: Any],
            "allowedExtensions": nullableArray(of: ["type": "string"]),
            "maxFileSizeMB": nullable("number"),
            "width": nullable("integer"),
            "height": nullable("integer"),
            "minWidth": nullable("integer"),
            "minHeight": nullable("integer"),
            "maxWidth": nullable("integer"),
            "maxHeight": nullable("integer"),
            "aspectRatios": nullableArray(of: ratio),
            "minDurationSeconds": nullable("number"),
            "maxDurationSeconds": nullable("number"),
            "minFramesPerSecond": nullable("number"),
            "maxFramesPerSecond": nullable("number"),
            "allowedVideoCodecs": nullableArray(of: ["type": "string"]),
            "allowedAudioCodecs": nullableArray(of: ["type": "string"]),
            "audio": ["type": "string", "enum": ["optional", "required", "forbidden"]] as [String: Any]
        ]
        return [
            "type": "object",
            "properties": properties,
            "required": properties.keys.sorted(),
            "additionalProperties": false
        ]
    }

    // MARK: - Response (pure, unit-tested)

    private struct MessagesResponse: Decodable {
        struct Block: Decodable {
            var type: String
            var text: String?
        }
        var content: [Block]?
        var stop_reason: String?
    }

    private struct ErrorResponse: Decodable {
        struct Detail: Decodable { var message: String? }
        var error: Detail?
    }

    static func parseResponse(_ data: Data) throws -> DeliverySpec {
        guard let response = try? JSONDecoder().decode(MessagesResponse.self, from: data) else {
            throw SpecImportError.unreadableResponse
        }
        switch response.stop_reason {
        case "refusal": throw SpecImportError.refused
        case "max_tokens": throw SpecImportError.truncated
        default: break
        }
        // Thinking blocks may precede the answer; the JSON is in the text block.
        let text = (response.content ?? []).filter { $0.type == "text" }.compactMap(\.text).joined()
        guard let json = text.data(using: .utf8), !text.isEmpty,
              var spec = try? JSONDecoder().decode(DeliverySpec.self, from: json) else {
            throw SpecImportError.unreadableResponse
        }
        spec.id = UUID()
        spec.isBuiltIn = false
        // Re-run the initializer's normalization (".MP4" -> "mp4", "jpeg" -> "jpg").
        spec.allowedExtensions = spec.allowedExtensions?.map(DeliverySpec.normalizedExtension)
        spec.allowedVideoCodecs = spec.allowedVideoCodecs?.map { $0.lowercased() }
        spec.allowedAudioCodecs = spec.allowedAudioCodecs?.map { $0.lowercased() }
        return spec
    }

    static func errorMessage(from data: Data) -> String {
        if let decoded = try? JSONDecoder().decode(ErrorResponse.self, from: data), let message = decoded.error?.message {
            return message
        }
        return String(decoding: data.prefix(300), as: UTF8.self)
    }
}
