import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

enum BackgroundMode: String, CaseIterable, Identifiable {
    case off = "Off", blur = "Blur", custom = "Custom"
    var id: String { rawValue }
}

enum VideoFormat: String, CaseIterable, Identifiable {
    case landscape = "Landscape", portrait = "Portrait"
    var id: String { rawValue }
    var size: CGSize { self == .landscape ? CGSize(width: 1280, height: 720) : CGSize(width: 720, height: 1280) }
}

enum VideoQuality: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case high = "High"
    case ultra = "Ultra"
    var id: String { rawValue }
    var size: CGSize {
        switch self { case .standard: return CGSize(width: 960, height: 540); case .high: return CGSize(width: 1280, height: 720); case .ultra: return CGSize(width: 1920, height: 1080) }
    }
    var frameRate: Double { self == .ultra ? 24 : 30 }
}

struct ProcessingSettings {
    var tracking = true
    var intensity: CGFloat = 1.8
    var background: BackgroundMode = .off
    var format: VideoFormat = .landscape
    var quality: VideoQuality = .high
    var mirrorStream = false
}

// All state is owned by the camera's serial processing queue.
final class FrameProcessor {
    let context = CIContext(options: [.cacheIntermediates: false])
    var settings = ProcessingSettings()
    var background: CIImage?
    private let segmentation = VNGeneratePersonSegmentationRequest()
    private let detection = VNDetectFaceRectanglesRequest()
    private var face: CGRect?
    private var lastFaceTime: TimeInterval = 0
    private var crop: CGRect?
    private var lastTime: TimeInterval = 0
    private var lastBounds = CGRect.zero

    init() {
        segmentation.qualityLevel = .balanced
        segmentation.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }

    func reset() {
        face = nil; crop = nil; lastTime = 0; lastFaceTime = 0
    }

    func process(_ buffer: CVPixelBuffer, time: TimeInterval) throws -> CIImage {
        var image = CIImage(cvPixelBuffer: buffer)
        let bounds = image.extent
        if bounds != lastBounds { reset(); lastBounds = bounds }
        let dt = lastTime == 0 ? 1.0 / 30 : min(0.25, max(0, time - lastTime))
        lastTime = time

        if settings.tracking {
            try VNImageRequestHandler(ciImage: image).perform([detection])
            if let target = Framing.subject(from: detection.results?.map(\.boundingBox) ?? [], previous: face) {
                face = target
                lastFaceTime = time
            } else if time - lastFaceTime > 1.0 { face = nil }
        } else { face = nil }

        if settings.background != .off {
            try VNImageRequestHandler(ciImage: image).perform([segmentation])
            if let result = segmentation.results?.first {
                let mask = CIImage(cvPixelBuffer: result.pixelBuffer)
                let scaledMask = mask.transformed(by: .init(scaleX: bounds.width / mask.extent.width, y: bounds.height / mask.extent.height))
                let replacement: CIImage?
                if settings.background == .blur {
                    replacement = image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 18]).cropped(to: bounds)
                } else { replacement = background.map { Self.fill($0, size: bounds.size) } }
                if let replacement {
                    let blend = CIFilter.blendWithMask()
                    blend.inputImage = image; blend.backgroundImage = replacement; blend.maskImage = scaledMask
                    image = blend.outputImage?.cropped(to: bounds) ?? image
                }
            }
        }
        let base = settings.quality.size
        let size = settings.format == .landscape ? base : CGSize(width: base.height, height: base.width)
        let aspect = size.width / size.height
        let target = Framing.crop(in: bounds, aspect: aspect, face: face, intensity: settings.intensity)
        crop = Framing.clamp(crop.map { Framing.interpolate($0, to: target, amount: CGFloat(1 - exp(-5 * dt))) } ?? target,
                             in: bounds, aspect: aspect)
        let rect = crop ?? target
        image = image.cropped(to: rect).transformed(by: .init(translationX: -rect.minX, y: -rect.minY))
            .transformed(by: .init(scaleX: size.width / rect.width, y: size.height / rect.height))
            .cropped(to: CGRect(origin: .zero, size: size))
        if settings.mirrorStream {
            image = image.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: size.width, ty: 0))
        }
        return image
    }

    static func fill(_ image: CIImage, size: CGSize) -> CIImage {
        let scale = max(size.width / image.extent.width, size.height / image.extent.height)
        let scaled = image.transformed(by: .init(scaleX: scale, y: scale))
        let rect = CGRect(x: scaled.extent.midX - size.width / 2, y: scaled.extent.midY - size.height / 2, width: size.width, height: size.height)
        return scaled.cropped(to: rect).transformed(by: .init(translationX: -rect.minX, y: -rect.minY))
    }
}

