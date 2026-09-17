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
    private var session: VTCompressionSession?
    private var size = CGSize.zero
    private var frameRate: Double = 30
    private var pending = 0
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

    func offer(_ image: CIImage, time: CMTime) {
        queue.async {
            guard self.running, let session = self.session, self.pending < 2,
                  let pool = VTCompressionSessionGetPixelBufferPool(session) else { return }
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess,
                  let buffer else { return }
            self.context.render(image, to: buffer, bounds: CGRect(origin: .zero, size: self.size), colorSpace: CGColorSpaceCreateDeviceRGB())
            self.pending += 1
            let duration = CMTime(seconds: 1 / self.frameRate, preferredTimescale: 90_000)
            let status = VTCompressionSessionEncodeFrame(session, imageBuffer: buffer, presentationTimeStamp: time,
                duration: duration, frameProperties: nil, infoFlagsOut: nil) { [weak self] status, _, sample in
                guard let self else { return }
                self.queue.async {
                    self.pending = max(0, self.pending - 1)
                    guard self.running, status == noErr, let sample,
                          let frame = Self.extract(sample) else { return }
                    self.onFrame?(frame)
                }
            }
            if status != noErr {
                self.pending = max(0, self.pending - 1)
                self.onError?("H.264 encoder rejected a frame (\(status)).")
            }
        }
    }

    private func createSession() -> Bool {
        let width = Int32(size.width), height = Int32(size.height)
        guard width > 0, height > 0 else { return false }
        let spec: CFDictionary
        if #available(iOS 17.4, *) {
            spec = [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: kCFBooleanTrue] as CFDictionary
        } else {
            spec = [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: kCFBooleanTrue] as CFDictionary
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
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: bitrate))
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: Int(frameRate * 2)))
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: Int(frameRate)))
        VTCompressionSessionPrepareToEncodeFrames(created)
        return true
    }

    private func stopInternal() {
        running = false
        if let session { VTCompressionSessionInvalidate(session) }
        session = nil
        pending = 0
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

