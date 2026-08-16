/// Settings for image-family outputs: Avif, Jpg, Png, Webp (ImageMagick
/// backend) and the intermediate PNG stage of Ico. Pdf reuses this struct's
/// scale/rotation but is produced with the ImageMagick job's PDF-specific
/// density handling — see `ImageMagickConversionJob`.
public struct ImageSettings: Codable, Equatable, Sendable {
    /// ImageQuality. Not used for Png (ImageMagick's PNG quality=95 default
    /// applies unconditionally, per ConversionJob_ImageMagick.cs:224-225 —
    /// PNG "quality" controls zlib compression effort, not visual fidelity).
    public var quality: Int

    /// ImageScale. 1.0 = 100%.
    public var scale: Double

    /// ImageRotation, degrees: 0, 90, 180, or 270.
    public var rotationDegrees: Int

    /// ImageClampSizePowerOf2 — used by the Ico pipeline's intermediate PNG.
    public var clampSizeToPowerOfTwo: Bool

    /// ImageMaximumSize, in pixels. 0/nil = unbounded.
    public var maximumSizePixels: Int?

    public init(
        quality: Int = 90,
        scale: Double = 1,
        rotationDegrees: Int = 0,
        clampSizeToPowerOfTwo: Bool = false,
        maximumSizePixels: Int? = nil
    ) {
        self.quality = quality
        self.scale = scale
        self.rotationDegrees = rotationDegrees
        self.clampSizeToPowerOfTwo = clampSizeToPowerOfTwo
        self.maximumSizePixels = maximumSizePixels
    }
}

/// Settings for the Pdf output type (image/document -> Pdf via ImageMagick).
public struct DocumentSettings: Codable, Equatable, Sendable {
    /// BaseDpiForPdfConversion in the Windows app — fixed at 200dpi,
    /// ConversionJob_ImageMagick.cs:12.
    public var densityDpi: Int

    public init(densityDpi: Int = 200) {
        self.densityDpi = densityDpi
    }
}
