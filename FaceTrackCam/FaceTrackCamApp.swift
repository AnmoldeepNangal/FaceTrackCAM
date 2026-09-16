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

// MARK: - Background Mode

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
            Color.black.ignoresSafeArea()

            if isBlackoutMode {
                // 1. OLED Screen Dimmer / Anti-Burn-In
                Color.black.ignoresSafeArea()
                    .overlay(
                        Text("BLACKOUT MODE ACTIVE\nCamera & Server Running\nTap anywhere to wake")
                            .multilineTextAlignment(.center)
                            .foregroundColor(Color(white: 0.2))
                            .font(.headline)
                    )
                    .onTapGesture {
                        isBlackoutMode = false
                        UIScreen.main.brightness = previousBrightness
                    }
            } else {
                // 2. Camera Video Feed
                if let frame = camera.currentFrame {
                    Image(decorative: frame, scale: 1.0, orientation: .up)
                        .resizable()
                        .scaledToFit()
                        .ignoresSafeArea()
                } else {
                    Text("Starting Camera...")
                        .foregroundColor(.white)
                }

                // 3. Status & HUD Overlay (Top)
                VStack {
                    HStack {
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Image(systemName: camera.batteryLevel > 0.2 ? "battery.100" : "battery.25")
                                Text("\(Int(camera.batteryLevel * 100))%")
                            }
                            .foregroundColor(camera.batteryLevel > 0.2 ? .white : .red)

                            HStack(spacing: 4) {
                                Image(systemName: "flame.fill")
                                Text(camera.thermalString)
                            }
                            .foregroundColor(camera.thermalColor)
                        }
                        .font(.caption)
                        .padding(8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)

                        Spacer()

                        Button(action: {
                            previousBrightness = UIScreen.main.brightness
                            UIScreen.main.brightness = 0.0
                            isBlackoutMode = true
                        }) {
                            Image(systemName: "moon.zzz.fill")
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.black.opacity(0.7))
                                .clipShape(Circle())
                        }
                    }
                    .padding()
                    Spacer()
                }

                // 4. User Interface Overlay (Bottom Controls)
                VStack {
                    Spacer()

                    VStack(spacing: 15) {
                        // Zoom Intensity Slider
                        HStack {
                            Text("Zoom")
                                .foregroundColor(.white)
                                .font(.caption)
                            Slider(value: $camera.zoomIntensity, in: 1.0...4.0)
                                .tint(.green)
                        }
                        .padding(.horizontal)

                        HStack(spacing: 10) {
                            // Lens Selector
                            Picker("Lens", selection: $camera.selectedCameraID) {
                                ForEach(camera.availableCameras, id: \.uniqueID) { cam in
                                    Text(cam.localizedName).tag(cam.uniqueID)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .padding(10)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(8)
                            .onChange(of: camera.selectedCameraID) { _, newID in
                                camera.switchCamera(cameraID: newID)
                            }

                            // Background Mode Selector (replaces old Blur toggle)
                            Picker("Background", selection: $camera.backgroundMode) {
                                ForEach(BackgroundMode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .frame(width: 200)
                            .padding(10)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(8)
                        }

                        // Saved-backgrounds gallery: pick an existing one, add a new one, or delete.
                        if camera.backgroundMode == .custom {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(camera.savedBackgrounds) { bg in
                                        ZStack(alignment: .topTrailing) {
                                            if let thumb = bg.thumbnail {
                                                Image(uiImage: thumb)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 48, height: 48)
                                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 6)
                                                            .stroke(camera.selectedBackgroundID == bg.id ? Color.green : Color.clear, lineWidth: 2)
                                                    )
                                                    .onTapGesture {
                                                        camera.selectSavedBackground(id: bg.id)
                                                    }
                                            }
                                            Button(action: { camera.deleteBackground(id: bg.id) }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.white)
                                                    .background(Circle().fill(Color.black.opacity(0.7)))
                                            }
                                            .offset(x: 5, y: -5)
                                        }
                                    }

                                    PhotosPicker(selection: $backgroundPickerItem, matching: .images) {
                                        Image(systemName: "plus")
                                            .foregroundColor(.white)
                                            .frame(width: 48, height: 48)
                                            .background(Color.white.opacity(0.15))
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                                .padding(8)
                            }
                            .frame(height: 64)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(8)
                            .onChange(of: backgroundPickerItem) { _, newItem in
                                Task {
                                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                                       let uiImage = UIImage(data: data) {
                                        camera.addBackground(uiImage: uiImage)
                                    }
                                    backgroundPickerItem = nil
                                }
                            }

                            if camera.savedBackgrounds.isEmpty {
                                Text("Tap + to add a background photo")
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                            }
                        }

                        HStack(spacing: 10) {
                            // Face Tracking Toggle
                            Toggle("Tracking", isOn: $camera.isFaceTrackingEnabled)
                                .toggleStyle(SwitchToggleStyle(tint: .green))
                                .padding(10)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(8)

                            // Exposure Lock Toggle
                            Toggle("AE/AF Lock", isOn: $camera.isExposureLocked)
                                .toggleStyle(SwitchToggleStyle(tint: .orange))
                                .padding(10)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(8)
                                .onChange(of: camera.isExposureLocked) { _, locked in
                                    camera.toggleExposureLock(lock: locked)
                                }

                            // Mirror Toggle — defaults on for front camera, off for back,
                            // but always overridable (useful since OBS often wants an
                            // un-mirrored feed regardless of which lens is active).
                            Toggle("Mirror", isOn: $camera.isMirrored)
                                .toggleStyle(SwitchToggleStyle(tint: .blue))
                                .padding(10)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(8)
                                .onChange(of: camera.isMirrored) { _, mirrored in
                                    camera.setMirrored(mirrored)
                                }
                        }

                        // OBS Connection Dashboard
                        VStack(spacing: 5) {
                            Text("WI-FI OBS URL:  \(camera.getWiFiAddress())")
                                .font(.subheadline)
                                .foregroundColor(.white)
                        }
                        .padding(10)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                    }
                    .padding(.bottom, 20)
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
    @Published var isMirrored: Bool = true
    @Published var zoomIntensity: CGFloat = 2.8

    @Published var availableCameras: [AVCaptureDevice] = []
    @Published var selectedCameraID: String = ""

    @Published var batteryLevel: Float = 1.0
    @Published var thermalString: String = "Normal"
    @Published var thermalColor: Color = .green

    // Saved custom backgrounds, persisted across launches.
    @Published var savedBackgrounds: [SavedBackground] = []
    @Published var selectedBackgroundID: UUID?

    var hasCustomBackground: Bool { customBackgroundImage != nil }

    private var captureSession = AVCaptureSession()
    private var currentFaceRect: CGRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)

    // Dedicated request for Neural Engine background segmentation
    private let segmentationRequest = VNGeneratePersonSegmentationRequest()
    private let context = CIContext()

    // The currently-active custom background, stored once as a CIImage so we don't
    // re-decode it on every frame. All reads (in captureOutput) and writes (in
    // activateBackground) are dispatched onto videoQueue below, so access is
    // serialized without needing a lock.
    private var customBackgroundImage: CIImage?

    // Single shared serial queue for all camera frame delivery + background-image
    // mutation. Previously this was re-created with `DispatchQueue(label: "videoQueue")`
    // in two different places, which does NOT give you the same queue — matching labels
    // don't merge queues, so that was a real, unsynchronized cross-thread race.
    private let videoQueue = DispatchQueue(label: "com.facetrackcam.videoQueue")

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var timer: Timer?

    // MARK: - Saved background persistence

    private let savedBackgroundIDsKey = "savedBackgroundIDs"
    private let selectedBackgroundIDKey = "selectedBackgroundID"

    private let backgroundsDirectory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Backgrounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    override init() {
        super.init()
        segmentationRequest.qualityLevel = .balanced
        loadCameras()
        startMJPEGServer()
        startHardwareMonitor()
        loadSavedBackgrounds()
    }

    // MARK: - Custom Background

    /// Called from the UI when the user picks a photo. Converts it to a CIImage
    /// (respecting EXIF orientation) then hops onto videoQueue — the same queue
    /// captureOutput runs on — to store it, so there's no race with the frame
    /// that's reading customBackgroundImage at the same moment.
    func setCustomBackground(uiImage: UIImage) {
        guard let ciImage = CIImage(image: uiImage, options: [.applyOrientationProperty: true]) else { return }
        videoQueue.async { [weak self] in
            self?.customBackgroundImage = ciImage
        }
    }

    /// Scales `image` up (aspect-fill) and center-crops it to exactly `targetSize`,
    /// normalizing its origin to (0,0) so it lines up with the live camera frame.
    private func scaledToFill(image: CIImage, targetSize: CGSize) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0, targetSize.width > 0, targetSize.height > 0 else { return image }

        let scale = max(targetSize.width / extent.width, targetSize.height / extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let scaledExtent = scaled.extent
        let cropX = scaledExtent.origin.x + (scaledExtent.width - targetSize.width) / 2
        let cropY = scaledExtent.origin.y + (scaledExtent.height - targetSize.height) / 2
        let cropRect = CGRect(x: cropX, y: cropY, width: targetSize.width, height: targetSize.height)

        return scaled
            .cropped(to: cropRect)
            .transformed(by: CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y))
    }

    func startHardwareMonitor() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.batteryLevel = UIDevice.current.batteryLevel

            let state = ProcessInfo.processInfo.thermalState
            switch state {
            case .nominal:
                self.thermalString = "Normal"
                self.thermalColor = .green
            case .fair:
                self.thermalString = "Warm"
                self.thermalColor = .yellow
            case .serious:
                self.thermalString = "Hot"
                self.thermalColor = .orange
            case .critical:
                self.thermalString = "Critical"
                self.thermalColor = .red
            @unknown default:
                break
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
            // Hop onto videoQueue before mutating `connections` — captureOutput reads/iterates
            // this same array on videoQueue, so this keeps all access on one serial queue
            // instead of racing across the listener's queue and the capture queue.
            self?.videoQueue.async {
                self?.connections.append(connection)
            }
        }
        listener?.start(queue: .global())
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        var currentCIImage = CIImage(cvPixelBuffer: pixelBuffer)

        // 1. Apply background replacement (Portrait blur or Custom image) if enabled
        if backgroundMode != .off {
            try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([segmentationRequest])
            if let maskPixelBuffer = segmentationRequest.results?.first?.pixelBuffer {
                let maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)

                // Scale the Neural Engine mask back up to full frame resolution
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
                    // If no photo has been picked yet, fall through with no replacement
                    // (backgroundImage stays nil) so the raw feed shows until one is chosen.

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

        // 2. Apply Face Tracking & Cropping
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

            // Dynamic Zoom based on slider
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
