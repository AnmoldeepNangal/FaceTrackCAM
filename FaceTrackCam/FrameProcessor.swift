import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

enum BackgroundMode: String, CaseIterable, Identifiable, Codable {
    case off = "Off", blur = "Blur", custom = "Custom"
    var id: String { rawValue }
}

enum VideoFormat: String, CaseIterable, Identifiable, Codable {
    case landscape = "Landscape", portrait = "Portrait"
    var id: String { rawValue }
    var size: CGSize { self == .landscape ? CGSize(width: 1280, height: 720) : CGSize(width: 720, height: 1280) }
}

enum VideoQuality: String, CaseIterable, Identifiable, Codable {
    case standard = "Standard"
    case high = "High"
    case ultra = "Ultra"
    var id: String { rawValue }
    var size: CGSize {
        switch self { case .standard: return CGSize(width: 960, height: 540); case .high: return CGSize(width: 1280, height: 720); case .ultra: return CGSize(width: 1920, height: 1080) }
    }
    var frameRate: Double { self == .ultra ? 24 : 30 }
    var label: String { "\(rawValue) · \(Int(size.width)) × \(Int(size.height)) · up to \(Int(frameRate)) FPS" }
}

enum SubjectMode: String, Codable, CaseIterable {
    case lock = "Lock me", group = "Auto widen"
}

struct ProcessingSettings: Codable {
    var tracking = true
    var intensity: CGFloat = 1.8
    var background: BackgroundMode = .off
    var format: VideoFormat = .landscape
    var quality: VideoQuality = .high
    var mirrorStream = false
    var subjectMode: SubjectMode = .lock
    var outputSize: CGSize {
        let base = quality.size
        return format == .landscape ? base : CGSize(width: base.height, height: base.width)
    }
}

// All state is owned by the camera's serial processing queue.
final class FrameProcessor {
    var settings = ProcessingSettings()
    var background: CIImage?
    private let segmentation = VNGeneratePersonSegmentationRequest()
    private let detection = VNDetectFaceRectanglesRequest()
    private var face: CGRect?
    private var lastFaceTime: TimeInterval = 0
    private var crop: CGRect?
    private var lastTime: TimeInterval = 0
    private var lastBounds = CGRect.zero
    private var lockedObservation: VNDetectedObjectObservation?
    private var sequence = VNSequenceRequestHandler()
    private var previousMode: SubjectMode = .lock
    private var groupFaces: CGRect?
    private var lastDetection: TimeInterval = 0
    private var lastGroupDetection: TimeInterval = 0
    private var lastTrack: TimeInterval = 0
    private var cachedMask: CIImage?
    private var lastSegmentation: TimeInterval = 0
    var relockRequested = false

    init() {
        segmentation.qualityLevel = .balanced
        segmentation.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }

    func reset() {
        face = nil; crop = nil; lastTime = 0; lastFaceTime = 0
        lockedObservation = nil; sequence = VNSequenceRequestHandler()
        groupFaces = nil; lastDetection = 0; lastGroupDetection = 0; lastTrack = 0
        cachedMask = nil; lastSegmentation = 0
    }

    func process(_ buffer: CVPixelBuffer, time: TimeInterval) throws -> CIImage {
        var image = CIImage(cvPixelBuffer: buffer)
        let bounds = image.extent
        if bounds != lastBounds { reset(); lastBounds = bounds }
        let dt = lastTime == 0 ? 1.0 / 30 : min(0.25, max(0, time - lastTime))
        lastTime = time

        if relockRequested || previousMode != settings.subjectMode {
            reset(); relockRequested = false; previousMode = settings.subjectMode
        }
        if settings.tracking {
            let detectGroup = settings.subjectMode == .group && (lastGroupDetection == 0 || time - lastGroupDetection >= 0.25)
            if detectGroup || (lockedObservation == nil && (lastDetection == 0 || time - lastDetection >= 0.25)) {
                try VNImageRequestHandler(ciImage: image).perform([detection])
                lastDetection = time
                let faces = detection.results?.map(\.boundingBox) ?? []
                if settings.subjectMode == .group {
                    groupFaces = faces.count > 1 ? Framing.group(faces) : nil
                    lastGroupDetection = time
                }
                if let target = Framing.subject(from: faces, previous: face) {
                    face = target; lastFaceTime = time
                    lockedObservation = Self.trackable(target) ? VNDetectedObjectObservation(boundingBox: target) : nil
                } else if time - lastFaceTime > 1 { face = nil; lockedObservation = nil }
            } else if time - lastTrack >= 1.0 / 15, let observation = lockedObservation {
                lastTrack = time
                if Self.trackable(observation.boundingBox) {
                    let request = VNTrackObjectRequest(detectedObjectObservation: observation)
                    request.trackingLevel = .fast
                    do {
                        try sequence.perform([request], on: buffer)
                        if let result = request.results?.first as? VNDetectedObjectObservation,
                           result.confidence > 0.45, Self.trackable(result.boundingBox) {
                            lockedObservation = result; face = result.boundingBox; lastFaceTime = time
                        } else { lockedObservation = nil; lastDetection = 0 }
                    } catch {
                        // Vision can reject a previously returned box after rapid
                        // motion. Discard that tracker and reacquire by detection.
                        lockedObservation = nil; lastDetection = 0
                    }
                } else { lockedObservation = nil; lastDetection = 0 }
                if lockedObservation == nil && time - lastFaceTime > 1 {
                    face = nil
                }
            }
        } else { face = nil; lockedObservation = nil; groupFaces = nil }

        if settings.background != .off {
            if cachedMask == nil || time - lastSegmentation >= 1.0 / 15 {
                try VNImageRequestHandler(ciImage: image).perform([segmentation])
                cachedMask = segmentation.results?.first.map { CIImage(cvPixelBuffer: $0.pixelBuffer) }
                lastSegmentation = time
            }
            if let mask = cachedMask {
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
        } else { cachedMask = nil }
        let size = settings.outputSize
        let aspect = size.width / size.height
        let target = settings.subjectMode == .group && groupFaces != nil
            ? Framing.groupCrop(in: bounds, aspect: aspect, faces: groupFaces!)
            : Framing.crop(in: bounds, aspect: aspect, face: face, intensity: settings.intensity)
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

    private static func trackable(_ box: CGRect) -> Bool {
        box.minX.isFinite && box.minY.isFinite && box.width.isFinite && box.height.isFinite &&
        box.minX >= 0 && box.minY >= 0 && box.maxX <= 1 && box.maxY <= 1 &&
        box.width >= 0.02 && box.height >= 0.02
    }
}

