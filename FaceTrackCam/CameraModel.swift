import SwiftUI
import AVFoundation
import CoreImage
import ImageIO
import Darwin

struct CameraChoice: Identifiable {
    let id: String
    let name: String
    let front: Bool
}

// Published properties and public actions belong to the main thread. Capture, device
// configuration and Vision state belong exclusively to captureQueue.
final class CameraModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var settings = ProcessingSettings() { didSet { updateSettings() } }
    @Published var mirrorPreview = true
    @Published private(set) var cameras: [CameraChoice] = []
    @Published private(set) var selectedCamera = ""
    @Published private(set) var frontCamera = false
    @Published private(set) var ready = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var starting = false
    @Published private(set) var streaming = false
    @Published private(set) var viewers = 0
    @Published private(set) var streamStarted: Date?
    @Published private(set) var token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    @Published private(set) var wifiAddress: String?
    @Published private(set) var battery: Int?
    @Published private(set) var thermal = "Normal"
    @Published private(set) var fps = 0
    @Published private(set) var hasBackground = false
    @Published private(set) var hasTorch = false
    @Published private(set) var torch = false
    @Published var exposure: Float = 0 { didSet { configureExposure() } }
    @Published var exposureLocked = false { didSet { configureExposure() } }
    @Published var whiteBalanceTemperature: Float = 4500 { didSet { configureWhiteBalance() } }
    @Published var whiteBalanceLocked = false { didSet { configureWhiteBalance() } }
    @Published var error: String?
    @Published var dimmed = false { didSet { applyDimming() } }
    @Published var oledSaverEnabled = false { didSet { dimmed = oledSaverEnabled } }

    let preview = PreviewFrames()
    private let session = AVCaptureSession()
    private let captureQueue = DispatchQueue(label: "cam.capture", qos: .userInitiated)
    private let processor = FrameProcessor()
    private let server = StreamServer()
    private let liveActivity = StreamLiveActivity()
    private let output = AVCaptureVideoDataOutput()
    private var device: AVCaptureDevice?
    private var desiredActive = false
    private var observers: [NSObjectProtocol] = []
    private var monitor: Timer?
    private var previousBrightness: CGFloat?
    private var previousIdleTimer: Bool?
    private var lastFrameTime: TimeInterval = 0
    private var statsTime: TimeInterval = 0
    private var statsFrames = 0
    private var lastErrorTime: TimeInterval = 0
    private var orientation: AVCaptureVideoOrientation = .portrait

    override init() {
        super.init()
        server.onStatus = { [weak self] status in
            guard let self else { return }
            self.starting = false
            if status.running && !self.streaming { self.streamStarted = Date() }
            self.streaming = status.running
            self.viewers = status.clients
            if !status.running { self.streamStarted = nil; self.dimmed = false }
            self.liveActivity.setStreaming(status.running, since: self.streamStarted)
            if let error = status.error { self.error = error }
            self.updateIdleTimer()
        }
        UIDevice.current.isBatteryMonitoringEnabled = true
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        monitor = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.updateMonitor() }
        observe(UIDevice.orientationDidChangeNotification, object: nil) { [weak self] _ in self?.updateOrientation() }
        observe(.AVCaptureSessionWasInterrupted, object: session) { [weak self] _ in
            self?.ready = false; self?.stopStream(); self?.error = "Camera interrupted. Return to the app to resume the preview."
        }
        observe(.AVCaptureSessionInterruptionEnded, object: session) { [weak self] _ in
            guard let self, self.desiredActive else { return }; self.activate()
        }
        observe(.AVCaptureSessionRuntimeError, object: session) { [weak self] notification in
            guard let self else { return }
            self.ready = false; self.stopStream()
            self.error = (notification.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription ?? "Camera stopped. Tap Retry."
        }
        updateMonitor()
    }

    deinit {
        monitor?.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver)
        server.stop()
        let session = session
        captureQueue.async { if session.isRunning { session.stopRunning() } }
    }

    private func observe(_ name: Notification.Name, object: Any?, action: @escaping (Notification) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main, using: action))
    }

    func activate() {
        desiredActive = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: permissionDenied = false; discoverAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.desiredActive else { return }
                    if granted { self.discoverAndStart() }
                    else { self.permissionDenied = true; self.error = "Allow camera access in Settings to use FaceTrackCam." }
                }
            }
        default: permissionDenied = true; error = "Allow camera access in Settings to use FaceTrackCam."
        }
    }

    func deactivate() {
        desiredActive = false; ready = false
        stopStream(); dimmed = false
        captureQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
            self.preview.put(nil)
            if let device = self.device, device.hasTorch, (try? device.lockForConfiguration()) != nil {
                device.torchMode = .off; device.unlockForConfiguration()
            }
        }
        torch = false
    }

    private func discoverAndStart() {
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera], mediaType: .video, position: .unspecified).devices
        cameras = devices.map { CameraChoice(id: $0.uniqueID, name: $0.localizedName, front: $0.position == .front) }
        guard let choice = devices.first(where: { $0.uniqueID == selectedCamera }) ?? devices.first(where: { $0.position == .front }) ?? devices.first else {
            error = "No camera is available on this device."; return
        }
        updateOrientation()
        switchCamera(choice.uniqueID)
    }

    func switchCamera(_ id: String) {
        ready = false
        let bias = exposure
        let locked = exposureLocked
        captureQueue.async {
            if self.device?.uniqueID == id && self.session.isRunning {
                DispatchQueue.main.async { self.ready = self.desiredActive }
                return
            }
            guard let candidate = AVCaptureDevice(uniqueID: id) else { self.report("The selected lens is unavailable."); return }
            do {
                let input = try AVCaptureDeviceInput(device: candidate)
                self.session.beginConfiguration()
                if self.session.canSetSessionPreset(.hd1920x1080) { self.session.sessionPreset = .hd1920x1080 }
                let oldInputs = self.session.inputs
                oldInputs.forEach(self.session.removeInput)
                guard self.session.canAddInput(input) else {
                    oldInputs.filter(self.session.canAddInput).forEach(self.session.addInput)
                    self.session.commitConfiguration(); self.report("Could not switch cameras."); return
                }
                self.session.addInput(input)
                if self.session.outputs.isEmpty {
                    self.output.alwaysDiscardsLateVideoFrames = true
                    self.output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    self.output.setSampleBufferDelegate(self, queue: self.captureQueue)
                    guard self.session.canAddOutput(self.output) else {
                        self.session.commitConfiguration(); self.report("Video output is unavailable."); return
                    }
                    self.session.addOutput(self.output)
                }
                self.device = candidate
                self.applyOrientation()
                self.session.commitConfiguration()
                try candidate.lockForConfiguration()
                if candidate.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }) {
                    candidate.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                    candidate.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
                }
                if candidate.isFocusModeSupported(.continuousAutoFocus) { candidate.focusMode = .continuousAutoFocus }
                if candidate.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { candidate.whiteBalanceMode = .continuousAutoWhiteBalance }
                if candidate.hasTorch { candidate.torchMode = .off }
                candidate.unlockForConfiguration()
                self.applyExposure(bias: bias, locked: locked)
                self.applyWhiteBalance(temperature: self.whiteBalanceTemperature, locked: self.whiteBalanceLocked)
                self.processor.reset(); self.preview.put(nil)
                if !self.session.isRunning { self.session.startRunning() }
                let running = self.session.isRunning
                DispatchQueue.main.async {
                    self.selectedCamera = id; self.frontCamera = candidate.position == .front
                    self.hasTorch = candidate.hasTorch; self.torch = false
                    self.ready = running && self.desiredActive
                    if !running { self.error = "Camera could not start. Tap Retry." }
                }
            } catch { self.report("Camera error: \(error.localizedDescription)") }
        }
    }

    func flipCamera() {
        if let next = cameras.first(where: { $0.front != frontCamera }) { switchCamera(next.id) }
    }

    private func updateSettings() {
        let snapshot = settings
        captureQueue.async {
            if self.processor.settings.format != snapshot.format { self.processor.reset() }
            self.processor.settings = snapshot
        }
    }

    func loadBackground(_ data: Data) {
        captureQueue.async {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1920, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else {
                self.report("This photo could not be opened. Choose another image."); return
            }
            self.processor.background = CIImage(cgImage: image)
            DispatchQueue.main.async { self.hasBackground = true; self.settings.background = .custom }
        }
    }

    func clearBackground() {
        settings.background = .off; hasBackground = false
        captureQueue.async { self.processor.background = nil }
    }

    private func configureExposure() {
        let bias = exposure, locked = exposureLocked
        captureQueue.async { self.applyExposure(bias: bias, locked: locked) }
    }

    private func applyExposure(bias: Float, locked: Bool) {
        guard let device else { return }
        do {
            try device.lockForConfiguration(); defer { device.unlockForConfiguration() }
            let mode: AVCaptureDevice.ExposureMode = locked ? .locked : .continuousAutoExposure
            if device.isExposureModeSupported(mode) { device.exposureMode = mode }
            device.setExposureTargetBias(max(device.minExposureTargetBias, min(device.maxExposureTargetBias, bias)))
        } catch { report("Exposure could not be changed: \(error.localizedDescription)") }
    }

    private func configureWhiteBalance() {
        let temperature = whiteBalanceTemperature
        let locked = whiteBalanceLocked
        captureQueue.async { self.applyWhiteBalance(temperature: temperature, locked: locked) }
    }

    private func applyWhiteBalance(temperature: Float, locked: Bool) {
        guard let device else { return }
        do {
            try device.lockForConfiguration(); defer { device.unlockForConfiguration() }
            guard device.isWhiteBalanceModeSupported(.locked) else { return }
            if !locked, device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
                return
            }
            let values = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: temperature, tint: 0)
            var gains = device.deviceWhiteBalanceGains(for: values)
            let maxGain = device.maxWhiteBalanceGain
            gains.redGain = min(max(gains.redGain, 1), maxGain)
            gains.greenGain = min(max(gains.greenGain, 1), maxGain)
            gains.blueGain = min(max(gains.blueGain, 1), maxGain)
            device.setWhiteBalanceModeLocked(with: gains)
        } catch { report("White balance could not be changed: \(error.localizedDescription)") }
    }

    func toggleTorch() {
        let on = !torch
        captureQueue.async {
            guard let device = self.device, device.hasTorch, device.isTorchAvailable else { self.report("Torch is unavailable on this lens."); return }
            do {
                try device.lockForConfiguration(); defer { device.unlockForConfiguration() }
                if on { try device.setTorchModeOn(level: 0.5) } else { device.torchMode = .off }
                DispatchQueue.main.async { self.torch = on }
            } catch { self.report(error.localizedDescription) }
        }
    }

    private func updateOrientation() {
        let newOrientation: AVCaptureVideoOrientation = .landscapeRight
        captureQueue.async { self.orientation = newOrientation; self.applyOrientation(); self.processor.reset() }
    }

    private func applyOrientation() {
        guard let connection = output.connection(with: .video) else { return }
        if connection.isVideoOrientationSupported { connection.videoOrientation = orientation }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = false
        }
    }

    func toggleStream() {
        if streaming || starting { stopStream(); return }
        guard ProcessInfo.processInfo.thermalState != .critical else { error = "Let the phone cool down before starting a stream."; return }
        guard ready else { error = "Wait for the camera preview before starting."; return }
        token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        starting = true
        server.start(token: token)
    }

    func stopStream() { starting = false; server.stop() }

    var wifiURL: String? { wifiAddress.map { "http://\($0):8080/stream.mjpg?token=\(token)" } }
    var usbURL: String { "http://127.0.0.1:18080/stream.mjpg?token=\(token)" }

    private func updateMonitor() {
        let level = UIDevice.current.batteryLevel
        battery = level < 0 ? nil : Int((level * 100).rounded())
        wifiAddress = Self.localAddress()
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "Normal"
        case .fair: thermal = "Warm"
        case .serious: thermal = "Hot · reduced FPS"
        case .critical:
            thermal = "Too hot"
            if streaming || starting { stopStream(); error = "Streaming stopped so the phone can cool down." }
        @unknown default: thermal = "Unknown"
        }
    }

    private func updateIdleTimer() {
        if streaming && oledSaverEnabled {
            dimmed = true
        }
        if streaming {
            if previousIdleTimer == nil { previousIdleTimer = UIApplication.shared.isIdleTimerDisabled }
            UIApplication.shared.isIdleTimerDisabled = true
        } else if let previous = previousIdleTimer {
            UIApplication.shared.isIdleTimerDisabled = previous; previousIdleTimer = nil
        }
    }

    private func applyDimming() {
        if dimmed {
            if previousBrightness == nil { previousBrightness = UIScreen.main.brightness }
            UIScreen.main.brightness = 0
        } else if let previous = previousBrightness { UIScreen.main.brightness = previous; previousBrightness = nil }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        autoreleasepool {
            let time = ProcessInfo.processInfo.systemUptime
            let thermal = ProcessInfo.processInfo.thermalState
            let limit: Double = thermal == .critical ? 5 : thermal == .serious ? 15 : 30
            guard time - lastFrameTime >= 0.9 / limit, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            lastFrameTime = time
            do {
                let image = try processor.process(buffer, time: time)
                // Materialize before releasing the camera buffer; preview and stream share it.
                guard let cg = processor.context.createCGImage(image, from: image.extent) else { return }
                let finished = CIImage(cgImage: cg)
                preview.put(finished); server.offer(finished)
                statsFrames += 1
                if time - statsTime >= 1 {
                    let value = statsTime == 0 ? 0 : Int((Double(statsFrames) / (time - statsTime)).rounded())
                    statsFrames = 0; statsTime = time
                    DispatchQueue.main.async { self.fps = value }
                }
            } catch {
                if time - lastErrorTime > 10 { lastErrorTime = time; report("Frame processing failed: \(error.localizedDescription)") }
            }
        }
    }

    private func report(_ message: String) { DispatchQueue.main.async { self.error = message } }

    private static func localAddress() -> String? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0 else { return nil }
        defer { freeifaddrs(addresses) }
        var cursor = addresses
        while let interface = cursor?.pointee {
            defer { cursor = interface.ifa_next }
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  String(cString: interface.ifa_name) == "en0" else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: host)
            }
        }
        return nil
    }
}

