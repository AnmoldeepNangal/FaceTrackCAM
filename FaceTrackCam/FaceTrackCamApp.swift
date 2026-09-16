import SwiftUI
import AVFoundation
import Vision
import Network
import CoreImage.CIFilterBuiltins
import PhotosUI // Added for the custom image picker

@main
struct FaceTrackCamApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @StateObject var camera = CameraTracker()
    @State private var isBlackoutMode = false
    @State private var previousBrightness: CGFloat = 0.5
    
    // State for the Photos Picker
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if isBlackoutMode {
                // 1. OLED Screen Dimmer (Retained)
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
                // 2. Camera Video Feed (Retained)
                if let frame = camera.currentFrame {
                    Image(decorative: frame, scale: 1.0, orientation: .up)
                        .resizable()
                        .scaledToFit()
                        .ignoresSafeArea()
                } else {
                    Text("Starting Camera...")
                        .foregroundColor(.white)
                }
                
                // 3. Status & HUD Overlay (Top) (Retained)
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
                
                // 4. User Interface Overlay (Bottom Controls) (Updated)
                VStack {
                    Spacer()
                    
                    VStack(spacing: 12) {
                        // Zoom Intensity Slider (Retained)
                        HStack {
                            Image(systemName: "minus.magnifyingglass")
                                .foregroundColor(.white)
                            Slider(value: $camera.zoomIntensity, in: 1.0...4.0)
                                .tint(.green)
                            Image(systemName: "plus.magnifyingglass")
                                .foregroundColor(.white)
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
                            .frame(maxWidth: .infinity)
                            .padding(10)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(8)
                            .onChange(of: camera.selectedCameraID) { newID in
                                camera.switchCamera(cameraID: newID)
                            }
                            
                            // NEW: Background Effects Selector & Custom Picker
                            VStack(spacing: 8) {
                                Picker("Background", selection: $camera.backgroundMode) {
                                    Text("Real").tag(CameraTracker.BackgroundMode.original)
                                    Text("Green").tag(CameraTracker.BackgroundMode.solidGreen)
                                    Text("Image").tag(CameraTracker.BackgroundMode.customImage)
                                }
                                .pickerStyle(SegmentedPickerStyle())
                                .background(Color.gray.opacity(0.3))
                                .cornerRadius(8)
                                
                                // Show the PhotosPicker button ONLY when custom image mode is selected
                                if camera.backgroundMode == .customImage {
                                    PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                                        HStack {
                                            Image(systemName: "photo.badge.plus")
                                            Text(camera.customBackgroundImage == nil ? "Select Image" : "Change Image")
                                        }
                                        .font(.caption)
                                        .foregroundColor(.cyan)
                                        .padding(8)
                                        .background(Color.black.opacity(0.8))
                                        .cornerRadius(6)
                                    }
                                    .onChange(of: selectedPhotoItem) { newItem in
                                        // Load the selected image and pass it to the camera tracker
                                        Task {
                                            if let data = try? await newItem?.loadTransferable(type: Data.self),
                                               let uiImage = UIImage(data: data) {
                                                camera.setCustomBackground(uiImage)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(8)
                        }
                        .padding(.horizontal, 5)
                        
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
                                .onChange(of: camera.isExposureLocked) { locked in
                                    camera.toggleExposureLock(lock: locked)
                                }
                        }
                        .padding(.horizontal, 5)
                        
                        // OBS Connection Dashboard
                        Text("Stream to OBS:  \(camera.getWiFiAddress())")
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(8)
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
    // Defines possible background replacements
    enum BackgroundMode {
        case original
        case solidGreen
        case customImage
    }
    
    @Published var currentFrame: CGImage?
    @Published var isFaceTrackingEnabled = true
    @Published var backgroundMode: BackgroundMode = .original // Default to original background
    @Published var customBackgroundImage: CIImage? // Holds processed custom background
    @Published var isExposureLocked = false
    @Published var zoomIntensity: CGFloat = 2.8
    
    @Published var availableCameras: [AVCaptureDevice] = []
    @Published var selectedCameraID: String = ""
    
    @Published var batteryLevel: Float = 1.0
    @Published var thermalString: String = "Normal"
    @Published var thermalColor: Color = .green
    
    private var captureSession = AVCaptureSession()
    private var currentFaceRect: CGRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    
    // Dedicated request for Neural Engine background segmentation
    private let segmentationRequest = VNGeneratePersonSegmentationRequest()
    private let context = CIContext()
    
    // Reuse solid colors to avoid reallocating
    private var greenScreenCIImage: CIImage?
    
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var timer: Timer?
    
    override init() {
        super.init()
        // 'balanced' is usually enough for streaming, 'accurate' is slower.
        segmentationRequest.qualityLevel = .balanced
        loadCameras()
        startMJPEGServer()
        startHardwareMonitor()
    }
    
    // Hardware Monitor (Retained)
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
    
    // Sets and prepares the custom background image selected by the user
    func setCustomBackground(_ image: UIImage) {
        if let ci = CIImage(image: image) {
            // Processing a large 100MB image every frame will kill performance.
            // We store the CIImage and scale it during the capture loop to match the frame size.
            // We ensure it's loaded onto the device
            DispatchQueue.main.async {
                self.customBackgroundImage = ci
            }
        }
    }
    
    // AE/WB Lock (Retained)
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
    
    // ... loadCameras(), switchCamera(), and startMJPEGServer() remain exactly the same as your original code ...
    
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
            output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
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
            self?.connections.append(connection)
        }
        listener?.start(queue: .global())
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        var currentCIImage = CIImage(cvPixelBuffer: pixelBuffer)
        let frameExtent = currentCIImage.extent
        
        // 1. Core Image pipeline for Background Effects
        if backgroundMode != .original {
            // Perform segmentation on the raw pixel buffer (more accurate for neural engine)
            try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([segmentationRequest])
            
            if let maskPixelBuffer = segmentationRequest.results?.first?.pixelBuffer {
                let maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)
                
                // Neural engine output is low-res; scale the mask back to 1080p
                let scaleX = frameExtent.width / maskImage.extent.width
                let scaleY = frameExtent.height / maskImage.extent.height
                let scaledMask = maskImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
                
                // Determine what goes behind the player
                var finalBackgroundImage: CIImage? = nil
                
                switch backgroundMode {
                case .solidGreen:
                    // Create a infinite solid green image and crop it to match the frame
                    finalBackgroundImage = CIImage(color: .green).cropped(to: frameExtent)
                case .customImage:
                    // Check if the user has selected an image
                    if let customImage = self.customBackgroundImage {
                        // We must scale and crop the custom background to perfectly match the 1080p stream aspect ratio
                        let bgScaleX = frameExtent.width / customImage.extent.width
                        let bgScaleY = frameExtent.height / customImage.extent.height
                        
                        // Use fill scaling logic (aspect fill)
                        let scale = max(bgScaleX, bgScaleY)
                        let scaledBG = customImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                        
                        // Crop to the center of the scaled background
                        let cropX = (scaledBG.extent.width - frameExtent.width) / 2
                        let cropY = (scaledBG.extent.height - frameExtent.height) / 2
                        finalBackgroundImage = scaledBG.cropped(to: CGRect(x: scaledBG.extent.origin.x + cropX, y: scaledBG.extent.origin.y + cropY, width: frameExtent.width, height: frameExtent.height))
                            .transformed(by: CGAffineTransform(translationX: -cropX, y: -cropY))
                        
                    } else {
                        // Fallback to green if "Custom Image" is selected but no image is picked
                        finalBackgroundImage = CIImage(color: .green).cropped(to: frameExtent)
                    }
                case .original:
                    break // Handled above
                }
                
                // Perform the blend
                if let bg = finalBackgroundImage {
                    let blendFilter = CIFilter.blendWithMask()
                    blendFilter.inputImage = currentCIImage // The player (foreground)
                    blendFilter.backgroundImage = bg        // The new green screen or custom image
                    blendFilter.maskImage = scaledMask    // The segmentation map
                    
                    if let blendedOutput = blendFilter.outputImage {
                        currentCIImage = blendedOutput
                    }
                }
            }
        }
        
        var finalCGImage: CGImage?
        
        // 2. Face Tracking & Cropping (Retained, dynamic zoom)
        if isFaceTrackingEnabled {
            let request = VNDetectFaceRectanglesRequest { [weak self] req, _ in
                guard let self = self, let results = req.results as? [VNFaceObservation], let face = results.first else { return }
                let target = face.boundingBox
                // Smoothing factor for face tracking
                self.currentFaceRect.origin.x += (target.origin.x - self.currentFaceRect.origin.x) * 0.1
                self.currentFaceRect.origin.y += (target.origin.y - self.currentFaceRect.origin.y) * 0.1
                self.currentFaceRect.size.width += (target.size.width - self.currentFaceRect.size.width) * 0.1
                self.currentFaceRect.size.height += (target.size.height - self.currentFaceRect.size.height) * 0.1
            }
            // Perform detection on the newly modified currentCIImage
            try? VNImageRequestHandler(ciImage: currentCIImage, options: [:]).perform([request])
            
            let width = currentCIImage.extent.width
            let height = currentCIImage.extent.height
            let faceX = currentFaceRect.origin.x * width
            let faceY = (1 - currentFaceRect.origin.y - currentFaceRect.size.height) * height
            let faceW = currentFaceRect.size.width * width
            let faceH = currentFaceRect.size.height * height
            
            // Dynamic Zoom based on slider
            let cropW = min(faceW * zoomIntensity, width)
            let cropH = cropW * (9.0/16.0) // Maintain 16:9
            let cropX = max(0, min((faceX + faceW/2) - (cropW / 2), width - cropW))
            let cropY = max(0, min((faceY + faceH/2) - (cropH / 2), height - cropH))
            
            let croppedCI = currentCIImage.cropped(to: CGRect(x: cropX, y: cropY, width: cropW, height: cropH))
            finalCGImage = context.createCGImage(croppedCI, from: croppedCI.extent)
        } else {
            // Full Uncropped Frame
            finalCGImage = context.createCGImage(currentCIImage, from: currentCIImage.extent)
        }
        
        guard let outputCG = finalCGImage else { return }
        
        // Update Local HUD
        DispatchQueue.main.async { self.currentFrame = outputCG }
        
        // 3. Broadcast Stream (MJPEG via TCP) (Retained)
        let uiImage = UIImage(cgImage: outputCG)
        if let jpeg = uiImage.jpegData(compressionQuality: 0.6) {
            let header = "--frame\r\nContent-Type: image/jpeg\r\nContent-Length: \(jpeg.count)\r\n\r\n"
            let data = header.data(using: .utf8)! + jpeg + "\r\n".data(using: .utf8)!
            self.connections.forEach { conn in
                conn.send(content: data, completion: .contentProcessed({ _ in }))
            }
        }
    }
    
    // IP Fetching logic (Retained)
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
