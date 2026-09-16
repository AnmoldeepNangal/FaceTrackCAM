import SwiftUI
import AVFoundation
import Vision
import Network
import CoreImage.CIFilterBuiltins
import PhotosUI // Required for native photo picker

// 1. Define our background modes
enum BackgroundMode: String, CaseIterable {
    case none = "Off"
    case blur = "Blur"
    case greenScreen = "Green Screen"
    case customImage = "Custom Image"
}

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
    
    // State for the native photo picker
    @State private var selectedItem: PhotosPickerItem?
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if isBlackoutMode {
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
                if let frame = camera.currentFrame {
                    Image(decorative: frame, scale: 1.0, orientation: .up)
                        .resizable()
                        .scaledToFit()
                        .ignoresSafeArea()
                } else {
                    Text("Starting Camera...")
                        .foregroundColor(.white)
                }
                
                // Status & HUD Overlay (Top)
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
                
                // User Interface Overlay (Bottom Controls)
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
                        
                        // Background Modes & Lens Picker
                        VStack(spacing: 10) {
                            HStack {
                                Picker("Lens", selection: $camera.selectedCameraID) {
                                    ForEach(camera.availableCameras, id: \.uniqueID) { cam in
                                        Text(cam.localizedName).tag(cam.uniqueID)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .padding(.horizontal, 10)
                                .background(Color.gray.opacity(0.3))
                                .cornerRadius(8)
                                .onChange(of: camera.selectedCameraID) { newID in
                                    camera.switchCamera(cameraID: newID)
                                }
                                
                                Spacer()
                            }
                            
                            // Multi-state Background Selector
                            Picker("Background", selection: $camera.backgroundMode) {
                                ForEach(BackgroundMode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .background(Color.white.opacity(0.8))
                            .cornerRadius(8)
                            
                            // Only show the Photo Picker button if "Custom Image" is selected
                            if camera.backgroundMode == .customImage {
                                PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
                                    HStack {
                                        Image(systemName: "photo.on.rectangle")
                                        Text("Select Background Image")
                                    }
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(Color.blue)
                                    .cornerRadius(8)
                                }
                                .onChange(of: selectedItem) { newItem in
                                    Task {
                                        // Load the photo as Data, convert to UIImage, then to CIImage
                                        if let data = try? await newItem?.loadTransferable(type: Data.self),
                                           let uiImage = UIImage(data: data),
                                           let ciImage = CIImage(image: uiImage) {
                                            DispatchQueue.main.async {
                                                camera.customBackgroundImage = ciImage
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(10)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(8)
                        
                        HStack(spacing: 10) {
                            Toggle("Tracking", isOn: $camera.isFaceTrackingEnabled)
                                .toggleStyle(SwitchToggleStyle(tint: .green))
                                .padding(10)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(8)
                            
                            Toggle("AE/AF Lock", isOn: $camera.isExposureLocked)
                                .toggleStyle(SwitchToggleStyle(tint: .orange))
                                .padding(10)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(8)
                                .onChange(of: camera.isExposureLocked) { locked in
                                    camera.toggleExposureLock(lock: locked)
                                }
                        }
                        
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
    @Published var backgroundMode: BackgroundMode = .none
    @Published var isExposureLocked = false
    @Published var zoomIntensity: CGFloat = 2.8
    @Published var customBackgroundImage: CIImage?
    
    @Published var availableCameras: [AVCaptureDevice] = []
    @Published var selectedCameraID: String = ""
    
    @Published var batteryLevel: Float = 1.0
    @Published var thermalString: String = "Normal"
    @Published var thermalColor: Color = .green
    
    private var captureSession = AVCaptureSession()
    private var currentFaceRect: CGRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    
    private let segmentationRequest = VNGeneratePersonSegmentationRequest()
    private let context = CIContext()
    
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
        } catch { print("Failed to lock camera: \(error)") }
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
        
        // 1. Hardware Background Replacement Switch
        if backgroundMode != .none {
            try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([segmentationRequest])
            if let maskPixelBuffer = segmentationRequest.results?.first?.pixelBuffer {
                let maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)
                
                let scaleX = currentCIImage.extent.width / maskImage.extent.width
                let scaleY = currentCIImage.extent.height / maskImage.extent.height
                let scaledMask = maskImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
                
                var generatedBackground: CIImage?
                
                switch backgroundMode {
                case .blur:
                    let blurFilter = CIFilter.gaussianBlur()
                    blurFilter.inputImage = currentCIImage
                    blurFilter.radius = 15.0
                    generatedBackground = blurFilter.outputImage?.cropped(to: currentCIImage.extent)
                    
                case .greenScreen:
                    // Solid Green output for OBS Chroma Keying
                    generatedBackground = CIImage(color: .green).cropped(to: currentCIImage.extent)
                    
                case .customImage:
                    if let customImg = customBackgroundImage {
                        // Math to Aspect-Fill the custom image without stretching it
                        let scale = max(currentCIImage.extent.width / customImg.extent.width,
                                        currentCIImage.extent.height / customImg.extent.height)
                        
                        let scaledBG = customImg.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                        
                        let xOffset = (scaledBG.extent.width - currentCIImage.extent.width) / 2.0
                        let yOffset = (scaledBG.extent.height - currentCIImage.extent.height) / 2.0
                        let centeredBG = scaledBG.transformed(by: CGAffineTransform(translationX: -xOffset, y: -yOffset))
                        
                        generatedBackground = centeredBG.cropped(to: currentCIImage.extent)
                    }
                case .none:
                    break
                }
                
                if let bg = generatedBackground {
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
        
        // 2. Face Tracking & Cropping
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
