import CoreImage
import CoreMedia
import CoreVideo
import VideoToolbox

/// Owns one real-time hardware encoder. All public methods run on `queue`.
final class H264Encoder {
    struct Frame {
        let nalUnits: [Data]
        let timestamp: UInt32
        let isKeyframe: Bool
    }

    var onFrame: ((Frame) -> Void)?
    var onError: ((String) -> Void)?

    private let queue = DispatchQueue(label: "facepull.h264", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let admission = NSLock()
    private var session: VTCompressionSession?
    private var size = CGSize.zero
    private var frameRate: Double = 30
    private var admitted = 0
    private var generation = 0
    private var forceKeyframe = false
    private var running = false

    func start(size: CGSize, frameRate: Double) {
        queue.async {
            self.stopInternal()
            self.size = size
            self.frameRate = frameRate
            self.running = self.createSession()
        }
    }

    func stop() { queue.async { self.stopInternal() } }

    func requestKeyframe() { queue.async { self.forceKeyframe = true } }

    func offer(_ image: CIImage, time: CMTime) {
        // Reject before dispatching: checking only on the encoder queue lets an
        // arbitrary backlog of stale CIImages retain camera buffers.
        admission.lock()
        guard admitted < 2 else { admission.unlock(); return }
        let generation = self.generation
        admitted += 1
        admission.unlock()
        queue.async {
            guard self.running, self.generation == generation, let session = self.session,
                  let pool = VTCompressionSessionGetPixelBufferPool(session) else { self.releaseAdmission(generation: generation); return }
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess,
                  let buffer else { self.releaseAdmission(generation: generation); return }
            self.context.render(image, to: buffer, bounds: CGRect(origin: .zero, size: self.size), colorSpace: self.colorSpace)
            let duration = CMTime(seconds: 1 / self.frameRate, preferredTimescale: 90_000)
            let properties = self.forceKeyframe ? [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue] as CFDictionary : nil
            self.forceKeyframe = false
            let status = VTCompressionSessionEncodeFrame(session, imageBuffer: buffer, presentationTimeStamp: time,
                duration: duration, frameProperties: properties, infoFlagsOut: nil) { [weak self] status, _, sample in
                guard let self else { return }
                self.queue.async {
                    self.releaseAdmission(generation: generation)
                    guard self.running, self.generation == generation, status == noErr, let sample,
                          let frame = Self.extract(sample) else { return }
                    self.onFrame?(frame)
                }
            }
            if status != noErr {
                self.releaseAdmission(generation: generation)
                self.onError?("H.264 encoder rejected a frame (\(status)).")
            }
        }
    }

    private func releaseAdmission(generation: Int) {
        admission.lock()
        if generation == self.generation { admitted = max(0, admitted - 1) }
        admission.unlock()
    }

    private func createSession() -> Bool {
        let width = Int32(size.width), height = Int32(size.height)
        guard width > 0, height > 0 else { return false }
        let spec: CFDictionary?
        if #available(iOS 17.4, *) {
            spec = [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: kCFBooleanTrue] as CFDictionary
        } else {
            // The explicit hardware-selection keys were introduced in iOS 17.4.
            // VideoToolbox chooses the encoder on older supported releases.
            spec = nil
        }
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        var created: VTCompressionSession?
        let status = VTCompressionSessionCreate(allocator: kCFAllocatorDefault, width: width, height: height,
            codecType: kCMVideoCodecType_H264, encoderSpecification: spec,
            imageBufferAttributes: attributes as CFDictionary, compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil, compressionSessionOut: &created)
        guard status == noErr, let created else {
            onError?("Hardware H.264 encoder is unavailable (\(status)).")
            return false
        }
        session = created
        let bitrate = max(1_000_000, min(12_000_000, Int(size.width * size.height * frameRate * 0.12)))
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_MaxFrameDelayCount, value: NSNumber(value: 1))
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: bitrate))
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: Int(frameRate)))
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: Int(frameRate)))
        VTCompressionSessionPrepareToEncodeFrames(created)
        return true
    }

    private func stopInternal() {
        running = false
        admission.lock()
        generation += 1
        admitted = 0
        admission.unlock()
        forceKeyframe = false
        if let session { VTCompressionSessionInvalidate(session) }
        session = nil
    }

    private static func extract(_ sample: CMSampleBuffer) -> Frame? {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return nil }
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        guard pts.isValid else { return nil }
        let stamp = UInt32(truncatingIfNeeded: Int64((pts.seconds * 90_000).rounded()))
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
        let key = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool != true
        var units: [Data] = []
        if key, let format = CMSampleBufferGetFormatDescription(sample) {
            for index in 0..<2 {
                var pointer: UnsafePointer<UInt8>?
                var length = 0
                var count = 0
                if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: index,
                    parameterSetPointerOut: &pointer, parameterSetSizeOut: &length,
                    parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil) == noErr,
                   let pointer { units.append(Data(bytes: pointer, count: length)) }
            }
        }
        var total = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
            totalLengthOut: &total, dataPointerOut: &dataPointer) == noErr,
              let dataPointer else { return nil }
        let bytes = UnsafeRawPointer(dataPointer).assumingMemoryBound(to: UInt8.self)
        var offset = 0
        while offset + 4 <= total {
            let length = Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16 |
                Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            offset += 4
            guard length > 0, offset + length <= total else { return nil }
            units.append(Data(bytes: bytes.advanced(by: offset), count: length))
            offset += length
        }
        guard !units.isEmpty else { return nil }
        return Frame(nalUnits: units, timestamp: stamp, isKeyframe: key)
    }
}
