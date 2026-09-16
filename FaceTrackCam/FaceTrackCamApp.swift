import SwiftUI
import AVFoundation
import Vision
import Network
import PhotosUI
import CoreImage.CIFilterBuiltins

@main
struct FaceTrackCamApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

enum BackgroundMode: String, CaseIterable {
    case off = "Off"
    case portrait = "Portrait"
    case custom = "Custom"
}

struct ContentView: View {
    @StateObject var camera = CameraTracker()
    @State private var isBlackoutMode = false
    @State private var previousBrightness: CGFloat = 0.5
    @State private var backgroundPickerItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            // 1. Absolute Black Background
            Color.black.ignoresSafeArea()

            if isBlackoutMode {
                // OLED Burn-in Protection Layer
                Color.black.ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 12) {
                            Image(systemName: "moon.zzz.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.gray.opacity(0.6))
                            Text("BLACKOUT MODE ACTIVE")
                                .font(.headline)
                                .foregroundColor(.gray)
                            Text("Camera, Tracking & Server running natively.\nTap anywhere to wake.")
                                .font(.caption)
                                .foregroundColor(.gray.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }
                    )
                    .onTapGesture {
                        isBlackoutMode = false
                        UIScreen.main.brightness = previousBrightness
                    }
            } else {
                // 2. The Camera Feed (Perfectly scaled, never stretched)
                if let frame = camera.currentFrame {
                    Image(decorative: frame, scale: 1.0, orientation: .up)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .ignoresSafeArea()
                } else {
                    VStack {
                        ProgressView().tint(.white)
                        Text("Starting Camera...").font(.caption).foregroundColor(.gray).padding(.top, 8)
                    }
                }

                // 3. The Control Overlay (Strictly inside Safe Area so it never gets cut off)
                VStack {
                    // --- TOP STATUS BAR ---
                    HStack {
                        // Hardware Pill
                        HStack(spacing: 4) {
                            Image(systemName: camera.batteryLevel > 0.2 ? "battery.100" : "battery.25")
                            Text("\(Int(camera.batteryLevel * 100))%")
                            Circle()
                                .fill(camera.thermalColor)
                                .frame(width: 6, height: 6)
                        }
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())

                        Spacer()

                        // OBS URL Pill
                        Text(camera.getWiFiAddress())
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())

                        Spacer()

                        // Blackout Button
                        Button(action: {
                            previousBrightness = UIScreen.main.brightness
                            UIScreen.main.brightness = 0.0
                            isBlackoutMode = true
                        }) {
                            Image(systemName: "moon.fill")
                                .font(.system(size: 12))
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 5)

                    Spacer()

                    // --- BOTTOM CONTROL DASHBOARD (Liquid Glass) ---
                    VStack(spacing: 16) {
                        
                        // Row 1: Zoom Slider
                        HStack {
                            Text("Zoom")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white.opacity(0.8))
                            
                            Slider(value: $camera.zoomIntensity, in: 1.0...4.0, step: 0.1)
                                .tint(.green)
                            
                            Text(String(format: "%.1fx", camera.zoomIntensity))
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.green)
                                .frame(width: 35, alignment: .trailing)
                        }

                        // Row 2: Lens & Background Selectors
                        HStack(spacing: 12) {
                            Picker("Lens", selection: $camera.selectedCameraID) {
                                ForEach(camera.availableCameras, id: \.uniqueID) { cam in
                                    Text(cam.localizedName).tag(cam.uniqueID)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.white)
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.4))
                            .cornerRadius(8)
                            .onChange(of: camera.selectedCameraID) { _, newID in
                                camera.switchCamera(cameraID: newID)
                            }

                            Spacer()

                            Picker("Background", selection: $camera.backgroundMode) {
                                ForEach(BackgroundMode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 160)

                            if camera.backgroundMode == .custom {
                                PhotosPicker(selection: $backgroundPickerItem, matching: .images) {
                                    Image(systemName: camera.hasCustomBackground ? "photo.fill" : "photo.badge.plus")
                                        .font(.system(size: 14))
                                        .foregroundColor(camera.hasCustomBackground ? .green : .white)
                                        .padding(8)
                                        .background(.black.opacity(0.4))
                                        .clipShape(Circle())
                                }
                                .onChange(of: backgroundPickerItem) { _, newItem in
                                    guard let item = newItem else { return }
                                    Task {
                                        if let data = try? await item.loadTransferable(type: Data.self),
                                           let uiImage = UIImage(data: data) {
                                            camera.setCustomBackground(uiImage: uiImage)
                                        }
                                    }
                                }
                            }
                        }

                        // Row 3: Tracking & Lock Toggles
                        HStack {
                            Toggle("Face Track", isOn: $camera.isFaceTrackingEnabled)
                                .font(.system(size: 12, weight: .bold))
                                .toggleStyle(SwitchToggleStyle(tint: .green))

                            Divider()
                                .frame(height: 16)
                                .background(Color.gray.opacity(0.5))
                                .padding(.horizontal, 10)

                            Toggle("AE/AF Lock", isOn: $camera.isExposureLocked)
                                .font(.system(size: 12, weight: .bold))
                                .toggleStyle(SwitchToggleStyle(tint: .orange))
                                .onChange(of: camera.isExposureLocked) { _, locked in
                                    camera.toggleExposureLock(lock: locked)
                                }
                        }
                    }
                    .padding(16)
                    .background(.ultraThinMaterial) // Liquid Glass effect
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.horizontal)
                    .padding(.bottom, 10)
                }
            }
        }
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
    }
}

class CameraTracker: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var currentFrame: CGImage?
    @Published var isFaceTrackingEnabled = true
    @Published var backgroundMode: BackgroundMode = .off
    @Published var isExposureLocked = false
    @Published var zoomIntensity: CGFloat = 2.8

    @Published var availableCameras: [AVCaptureDevice] = []
    @Published var selectedCameraID: String = ""

    @Published var batteryLevel: Float = 1.0
    @Published var thermalString: String = "Normal"
    @Published var thermalColor: Color = .green

    var hasCustomBackground: Bool { customBackgroundImage != nil }

    private var captureSession = AVCaptureSession()
    private var currentFaceRect: CGRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)

    private let segmentationRequest = VNGeneratePersonSegmentationRequest()
    private let context = CIContext()
    private var customBackgroundImage: CIImage?
    private let videoQueue = DispatchQueue(label: "com.facetrackcam.videoQueue")

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var timer: Timer?

    override init() {
        super.init()
        segmentationRequest.qualityLevel = .balanced
        loadCameras()
        startMJPEGServer()
        startHardwareMonitor()
    }

    func setCustomBackground(uiImage: UIImage) {
        guard let ciImage = CIImage(image: uiImage, options: [.applyOrientationProperty: true]) else { return }
        videoQueue.async { [weak self] in
            self?.customBackgroundImage = ciImage
        }
    }

    private func scaledToFill(image: CIImage, targetSize: CGSize) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0, targetSize.width > 0, targetSize.height > 0 else { return image }
        let scale = max(targetSize.width / extent.width, targetSize.height / extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let scaledExtent = scaled.extent
        let cropX = scaledExtent.origin.x + (scaledExtent.width - targetSize.width) / 2
        let cropY = scaledExtent.origin.y + (scaledExtent.height - targetSize.height) / 2
        let cropRect = CGRect(x: cropX, y: cropY, width: targetSize.width, height: targetSize.height)
        return scaled.cropped(to: cropRect).transformed(by: CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y))
    }

    func startHardwareMonitor() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.batteryLevel = UIDevice.current.batteryLevel
            let state = ProcessInfo.processInfo.thermalState
            switch state {
            case .nominal: self.thermalString = "Normal"; self.thermalColor = .green
            case .fair: self.thermalString = "Warm"; self.thermalColor = .yellow
            case .serious: self.thermalString = "Hot"; self.thermalColor = .orange
            case .critical: self.thermalString = "Critical"; self.thermalColor = .red
            @unknown default: break
            }
        }
    }

    func toggleExposureLock(lock: Bool) {
        guard let device = captureSession.inputs.compactMap({ $0 as? AVCaptureDeviceInput }).first?.device else { return }
        do {
            try device.lockForConfiguration()
            if lock {
                if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
                if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }
                if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
            } else {
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            }
            device.unlockForConfiguration()
        } catch {
            print("Failed to lock camera properties: \(error)")
        }
    }

    func loadCameras() {
        let types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera, .builtInTrueDepthCamera]
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified)
        DispatchQueue.main.async {
            self.availableCameras = discovery.devices
            if let front = self.availableCameras.first(where: { $0.position == .front }) {
                self.selectedCameraID = front.uniqueID
                self.switchCamera(cameraID: front.uniqueID)
            }
        }
    }

    func switchCamera(cameraID: String) {
        guard let device = availableCameras.first(where: { $0.uniqueID == cameraID }) else { return }
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .hd1920x1080
        captureSession.inputs.forEach { captureSession.removeInput($0) }
        if let input = try? AVCaptureDeviceInput(device: device), captureSession.canAddInput(input) { captureSession.addInput(input) }
        if captureSession.outputs.isEmpty {
            let output = AVCaptureVideoDataOutput()
            output.setSampleBufferDelegate(self, queue: videoQueue)
            if captureSession.canAddOutput(output) { captureSession.addOutput(output) }
        }
        if let output = captureSession.outputs.first as? AVCaptureVideoDataOutput, let connection = output.connection(with: .video) {
            
            // LOCKS THE SENSOR TO TRUE PORTRAIT (9:16)
            connection.videoOrientation = .portrait
            if device.position == .front && connection.isVideoMirroringSupported { connection.isVideoMirrored = true }
        }
        captureSession.commitConfiguration()
        if !captureSession.isRunning { DispatchQueue.global(qos: .userInitiated).async { self.captureSession.startRunning() } }
    }

    func startMJPEGServer() {
        listener = try? NWListener(using: .tcp, on: 8080)
        listener?.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .global())
            let header = "HTTP/1.1 200 OK\r\nContent-Type: multipart/x-mixed-replace; boundary=frame\r\n\r\n"
            connection.send(content: header.data(using: .utf8)!, completion: .contentProcessed({ _ in }))
            self?.videoQueue.async {
                self?.connections.append(connection)
            }
        }
        listener?.start(queue: .global())
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        var currentCIImage = CIImage(cvPixelBuffer: pixelBuffer)

        if backgroundMode != .off {
            try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([segmentationRequest])
            if let maskPixelBuffer = segmentationRequest.results?.first?.pixelBuffer {
                let maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)
                let scaleX = currentCIImage.extent.width / maskImage.extent.width
                let scaleY = currentCIImage.extent.height / maskImage.extent.height
                let scaledMask = maskImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

                var backgroundImage: CIImage?
                switch backgroundMode {
                case .portrait:
                    let blurFilter = CIFilter.gaussianBlur()
                    blurFilter.inputImage = currentCIImage
                    blurFilter.radius = 15.0
                    backgroundImage = blurFilter.outputImage?.cropped(to: currentCIImage.extent)
                case .custom:
                    if let customBG = customBackgroundImage {
                        backgroundImage = scaledToFill(image: customBG, targetSize: currentCIImage.extent.size)
                    }
                case .off:
                    backgroundImage = nil
                }

                if let bg = backgroundImage {
                    let blendFilter = CIFilter.blendWithMask()
                    blendFilter.inputImage = currentCIImage
                    blendFilter.backgroundImage = bg
                    blendFilter.maskImage = scaledMask
                    if let blendedOutput = blendFilter.outputImage {
                        currentCIImage = blendedOutput
                    }
                }
            }
        }

        var finalCGImage: CGImage?

        if isFaceTrackingEnabled {
            let request = VNDetectFaceRectanglesRequest { [weak self] req, _ in
                guard let self = self, let results = req.results as? [VNFaceObservation], let face = results.first else { return }
                let target = face.boundingBox
                self.currentFaceRect.origin.x += (target.origin.x - self.currentFaceRect.origin.x) * 0.1
                self.currentFaceRect.origin.y += (target.origin.y - self.currentFaceRect.origin.y) * 0.1
                self.currentFaceRect.size.width += (target.size.width - self.currentFaceRect.size.width) * 0.1
                self.currentFaceRect.size.height += (target.size.height - self.currentFaceRect.size.height) * 0.1
            }
            try? VNImageRequestHandler(ciImage: currentCIImage, options: [:]).perform([request])

            let width = currentCIImage.extent.width
            let height = currentCIImage.extent.height
            let faceX = currentFaceRect.origin.x * width
            let faceY = (1 - currentFaceRect.origin.y - currentFaceRect.size.height) * height
            let faceW = currentFaceRect.size.width * width
            let faceH = currentFaceRect.size.height * height

            // MATHEMATICALLY LOCKED TO 9:16 VERTICAL ASPECT RATIO
            let cropW = min(faceW * zoomIntensity, width)
            let cropH = cropW * (16.0 / 9.0)
            let cropX = max(0, min((faceX + faceW/2) - (cropW / 2), width - cropW))
            let cropY = max(0, min((faceY + faceH/2) - (cropH / 2), height - cropH))

            let croppedCI = currentCIImage.cropped(to: CGRect(x: cropX, y: cropY, width: cropW, height: cropH))
            finalCGImage = context.createCGImage(croppedCI, from: croppedCI.extent)
        } else {
            finalCGImage = context.createCGImage(currentCIImage, from: currentCIImage.extent)
        }

        guard let outputCG = finalCGImage else { return }
        DispatchQueue.main.async { self.currentFrame = outputCG }

        let uiImage = UIImage(cgImage: outputCG)
        if let jpeg = uiImage.jpegData(compressionQuality: 0.6) {
            let header = "--frame\r\nContent-Type: image/jpeg\r\nContent-Length: \(jpeg.count)\r\n\r\n"
            let data = header.data(using: .utf8)! + jpeg + "\r\n".data(using: .utf8)!
            self.connections.forEach { conn in
                conn.send(content: data, completion: .contentProcessed({ _ in }))
            }
        }
    }

    func getWiFiAddress() -> String {
        var address = "Not Connected to Wi-Fi"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                guard let interface = ptr?.pointee else { continue }
                if interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                    if String(cString: interface.ifa_name) == "en0" {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                        address = "http://\(String(cString: hostname)):8080"
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        return address
    }
}
