import Foundation

/// Example delivery specs shipped with the app. They are deliberately
/// generic ("vertical video ad") rather than copies of any one platform's
/// current spec — real specs change often, so teams should duplicate one
/// and adjust it (or paste their partner's spec text into the AI importer).
public enum DefaultSpecs {
    /// Stable IDs so a reset can replace the built-ins in place.
    private static func id(_ suffix: String) -> UUID {
        UUID(uuidString: "5BEC0000-0000-4000-8000-\(suffix)")!
    }

    public static let verticalVideoAd = DeliverySpec(
        id: id("000000000001"),
        name: "Vertical video ad (9:16)",
        notes: "Example spec — check your ad network's current requirements.",
        mediaKinds: [.video],
        allowedExtensions: ["mp4", "mov"],
        maxFileSizeMB: 30,
        width: 1080, height: 1920,
        aspectRatios: [.vertical9x16],
        minDurationSeconds: 5, maxDurationSeconds: 60,
        maxFramesPerSecond: 60,
        allowedVideoCodecs: ["h264"],
        allowedAudioCodecs: ["aac"],
        audio: .required,
        isBuiltIn: true
    )

    public static let landscapeVideoAd = DeliverySpec(
        id: id("000000000002"),
        name: "Landscape video ad (16:9)",
        notes: "Example spec — check your ad network's current requirements.",
        mediaKinds: [.video],
        allowedExtensions: ["mp4", "mov"],
        maxFileSizeMB: 50,
        width: 1920, height: 1080,
        aspectRatios: [.landscape16x9],
        minDurationSeconds: 5, maxDurationSeconds: 60,
        maxFramesPerSecond: 60,
        allowedVideoCodecs: ["h264"],
        allowedAudioCodecs: ["aac"],
        audio: .required,
        isBuiltIn: true
    )

    public static let squareVideoAd = DeliverySpec(
        id: id("000000000003"),
        name: "Square video ad (1:1)",
        notes: "Example spec — check your ad network's current requirements.",
        mediaKinds: [.video],
        allowedExtensions: ["mp4"],
        maxFileSizeMB: 30,
        width: 1080, height: 1080,
        aspectRatios: [.square1x1],
        minDurationSeconds: 5, maxDurationSeconds: 30,
        maxFramesPerSecond: 60,
        allowedVideoCodecs: ["h264"],
        audio: .optional,
        isBuiltIn: true
    )

    public static let storeScreenshotPortrait = DeliverySpec(
        id: id("000000000004"),
        name: "Store screenshot (portrait 1290×2796)",
        notes: "Example: a 6.7\" phone screenshot size. Stores accept several sizes — duplicate and adjust.",
        mediaKinds: [.image],
        allowedExtensions: ["png", "jpg"],
        maxFileSizeMB: 8,
        width: 1290, height: 2796,
        isBuiltIn: true
    )

    public static let chatAttachment = DeliverySpec(
        id: id("000000000005"),
        name: "Chat / email attachment (≤ 25 MB)",
        notes: "Any file type; only the size matters.",
        maxFileSizeMB: 25,
        isBuiltIn: true
    )

    public static let all: [DeliverySpec] = [
        verticalVideoAd, landscapeVideoAd, squareVideoAd, storeScreenshotPortrait, chatAttachment
    ]
}
