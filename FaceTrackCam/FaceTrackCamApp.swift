import SwiftUI
import AVFoundation
import Vision
import Network
import CoreImage.CIFilterBuiltins

@main
struct FaceTrackCamApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @StateObject var camera = CameraTracker()
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Camera Preview
            if let frame = camera.currentFrame {
                Image(decorative: frame, scale: 1.0, orientation: .up)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
            } else {
                Text("Starting Camera...").foregroundColor(.white)
            }
            
            // UI Overlay
            VStack {
                // Top Row: Lens & Face Track
                HStack(spacing: 12) {
                    Picker("Lens", selection: $camera.selectedCameraID) {
                        ForEach(camera.availableCameras, id: \.uniqueID) { cam in
                            Text(cam.localizedName).tag(cam.uniqueID)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .padding(8)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(8)
                    
                    Spacer()
                    
                    Toggle("Face Tracking", isOn: $camera.isFaceTrackingEnabled)
                        .toggleStyle(SwitchToggleStyle(tint: .green))
                        .padding(8)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(8)
                        .frame(width: 170)
                }
                .padding()
                
                // NEW FEATURE: Exposure Lock
                HStack {
                    Spacer()
                    Toggle("Lock Exposure", isOn: $camera.isExposureLocked)
                        .toggleStyle(SwitchToggleStyle(tint: .yellow))
                        .padding(8)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(8)
                        .frame(width: 170)
                }
                .padding(.horizontal)
                
                // Zoom Slider
                if camera.isFaceTrackingEnabled {
                    HStack {
                        Text("Zoom: \(String(format: "%.1fx", camera.zoomLevel))")
                            .font(.system(size: 14, weight: .bold)).foregroundColor(.white).frame(width: 80, alignment: .leading)
                        Slider(value: $camera.zoomLevel, in: 1.0...3.0, step: 0.1).accentColor(.green)
                    }
                    .padding(14).background(Color.black.opacity(0.75)).cornerRadius(8).padding()
                }
                
                Spacer()
                
                // URLs
                VStack(spacing: 4) {
                    Text("WIRED OBS:  http://127.0.0.1:8080").font(.headline).foregroundColor(.green)
                    Text("WI-FI OBS:  \(camera.getWiFiAddress())").font(.subheadline).foregroundColor(.white)
                }
                .padding(10).background(Color.black.opacity(0.75)).cornerRadius(10).padding(.bottom, 15)
            }
        }
        .onChange(of: camera.selectedCameraID) { id in camera.switchCamera(cameraID: id) }
        .onChange(of: camera.isExposureLocked) { _ in camera.updateExposureLock() }
    }
}

class CameraTracker: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var currentFrame: CGImage?
    @Published var isFaceTrackingEnabled = true
    @Published var isExposureLocked = false // NEW
    @Published var zoomLevel: Double = 1.5
    @Published var availableCameras: [AVCaptureDevice] = []
    @Published var selectedCameraID: String = ""
    
    private var captureSession = AVCaptureSession()
    private var currentFaceRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    
    override init() {
        super.init()
        loadCameras()
        startMJPEGServer()
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
        
        if let input = try? AVCaptureDeviceInput(device: device), captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }
        
        if captureSession.outputs.isEmpty {
            let output = AVCaptureVideoDataOutput()
            output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
            if captureSession.canAddOutput(output) { captureSession.addOutput(output) }
        }
        
        if let output = captureSession.outputs.first as? AVCaptureVideoDataOutput, let conn = output.connection(with: .video) {
            conn.videoOrientation = .landscapeRight
            if device.position == .front && conn.isVideoMirroringSupported { conn.isVideoMirrored = true }
        }
        captureSession.commitConfiguration()
        
        if !captureSession.isRunning { DispatchQueue.global(qos: .userInitiated).async { self.captureSession.startRunning() } }
        updateExposureLock()
    }
    
    // NEW FEATURE LOGIC: Exposure Lock
    func updateExposureLock() {
        guard let device = availableCameras.first(where: { $0.uniqueID == selectedCameraID }) else { return }
        do {
            try device.lockForConfiguration()
            if device.isExposureModeSupported(isExposureLocked ? .locked : .continuousAutoExposure) {
                device.exposureMode = isExposureLocked ? .locked : .continuousAutoExposure
            }
            if device.isWhiteBalanceModeSupported(isExposureLocked ? .locked : .continuousAutoWhiteBalance) {
                device.whiteBalanceMode = isExposureLocked ? .locked : .continuousAutoWhiteBalance
            }
            device.unlockForConfiguration()
        } catch {
            print("Could not lock exposure")
        }
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
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let width = ciImage.extent.width
        let height = ciImage.extent.height
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
            try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([request])
            
            let centerX = (currentFaceRect.origin.x + currentFaceRect.size.width / 2.0) * width
            let centerY = (currentFaceRect.origin.y + currentFaceRect.size.height * 0.45) * height
            let multiplier = max(1.4, 4.2 / CGFloat(zoomLevel))
            var cropW = min(width, currentFaceRect.size.width * width * multiplier)
            var cropH = cropW * (9.0 / 16.0)
            
            if cropH > height { cropH = height; cropW = height * (16.0 / 9.0) }
            
            let cropX = max(0, min(centerX - (cropW / 2.0), width - cropW))
            let cropY = max(0, min(centerY - (cropH / 2.0), height - cropH))
            
            let croppedCI = ciImage.cropped(to: CGRect(x: cropX, y: cropY, width: cropW, height: cropH))
                .transformed(by: CGAffineTransform(translationX: -cropX, y: -cropY))
                .transformed(by: CGAffineTransform(scaleX: 1920.0 / cropW, y: 1920.0 / cropW))
            finalCGImage = ciContext.createCGImage(croppedCI, from: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        } else {
            finalCGImage = ciContext.createCGImage(ciImage, from: ciImage.extent)
        }
        
        guard let outputCG = finalCGImage else { return }
        DispatchQueue.main.async { self.currentFrame = outputCG }
        
        if let jpeg = UIImage(cgImage: outputCG).jpegData(compressionQuality: 0.6) {
            let data = "--frame\r\nContent-Type: image/jpeg\r\nContent-Length: \(jpeg.count)\r\n\r\n".data(using: .utf8)! + jpeg + "\r\n".data(using: .utf8)!
            connections.forEach { $0.send(content: data, completion: .contentProcessed({ _ })) }
        }
    }
    
    func getWiFiAddress() -> String {
        var address = "Not Connected"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                guard let interface = ptr?.pointee else { continue }
                if interface.ifa_addr.pointee.sa_family == UInt8(AF_INET), String(cString: interface.ifa_name) == "en0" {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len), &host, socklen_t(host.count), nil, socklen_t(0), NI_NUMERICHOST)
                    address = "http://\(String(cString: host)):8080"
                }
            }
            freeifaddrs(ifaddr)
        }
        return address
    }
}
