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
    @State private var showSettingsSheet = false

    var body: some View {
        ZStack {
            // Edge-to-Edge Native Camera Background
            Color.black.ignoresSafeArea()

            if isBlackoutMode {
                Color.black.ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 12) {
                            Image(systemName: "moon.zzz.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                            Text("Blackout Mode Active")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("Server & tracking running in background.\nTap anywhere to wake.")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                    )
                    .onTapGesture {
                        isBlackoutMode = false
                        UIScreen.main.brightness = previousBrightness
                    }
            } else {
                if let frame = camera.currentFrame {
                    Image(decorative: frame, scale: 1.0, orientation: .up)
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                        Text("Initializing Camera...")
                            .foregroundColor(.gray)
                            .font(.subheadline)
                    }
                }

                // Top Minimalist Status Bar (Apple Style)
                VStack {
                    HStack(spacing: 8) {
                        // Hardware Status Pill
                        HStack(spacing: 6) {
                            Image(systemName: camera.batteryLevel > 0.2 ? "battery.100" : "battery.25")
                            Text("\(Int(camera.batteryLevel * 100))%")
                            
                            Circle()
                                .fill(camera.thermalColor)
                                .frame(width: 6, height: 6)
                            Text(camera.thermalString)
                        }
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())

                        Spacer()

                        // Blackout Mode Button
                        Button(action: {
                            previousBrightness = UIScreen.main.brightness
                            UIScreen.main.brightness = 0.0
                            isBlackoutMode = true
                        }) {
                            Image(systemName: "moon.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }

                        // Settings / Control Drawer Toggle
                        Button(action: {
                            showSettingsSheet.toggle()
                        }) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    Spacer()
                }
            }
        }
        .sheet(isPresented: $showSettingsSheet) {
            // Apple-style Sheet Control Panel
            NavigationView {
                Form {
                    Section(header: Text("Connection & Output")) {
                        HStack {
                            Text("Wi-Fi OBS URL")
                            Spacer()
                            Text(camera.getWiFiAddress())
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                    }

                    Section(header: Text("Camera Optics & Framing")) {
                        Picker("Active Lens", selection: $camera.selectedCameraID) {
                            ForEach(camera.availableCameras, id: \.uniqueID) { cam in
                                Text(cam.localizedName).tag(cam.uniqueID)
                            }
                        }
                        .onChange(of: camera.selectedCameraID) { _, newID in
                            camera.switchCamera(cameraID: newID)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Zoom Intensity")
                                Spacer()
                                Text(String(format: "%.1fx", camera.zoomIntensity))
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $camera.zoomIntensity, in: 1.0...4.0, step: 0.1)
                                .tint(.accentColor)
                        }
                        .padding(.vertical, 4)

                        Toggle("AI Face Tracking", isOn: $camera.isFaceTrackingEnabled)
                    }

                    Section(header: Text("Environment & Background")) {
                        Picker("Background Mode", selection: $camera.backgroundMode) {
                            ForEach(BackgroundMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue.capitalized).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.vertical, 4)

                        if camera.backgroundMode == .custom {
                            PhotosPicker(selection: $backgroundPickerItem, matching: .images) {
                                HStack {
                                    Label(camera.hasCustomBackground ? "Change Custom Background" : "Select Background Image", 
                                          systemImage: "photo.on.rectangle")
                                    Spacer()
                                    if camera.hasCustomBackground {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                }
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

                    Section(header: Text("Sensor Pro Controls")) {
                        Toggle("Lock Exposure & White Balance", isOn: $camera.isExposureLocked)
                            .onChange(of: camera.isExposureLocked) { _, locked in
                                camera.toggleExposureLock(lock: locked)
                            }
                    }
                }
                .navigationTitle("Camera Controls")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showSettingsSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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
            connection.videoOrientation = .landscapeRight
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

            let cropW = min(faceW * zoomIntensity, width)
            let cropH = cropW * (9.0/16.0)
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
