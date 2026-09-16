import SwiftUI
import AVFoundation
import Vision
import Network

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
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // 1. Live Camera Preview
            if let frame = camera.currentFrame {
                Image(decorative: frame, scale: 1.0, orientation: .up)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
            } else {
                Text("Starting Camera...")
                    .foregroundColor(.white)
            }
            
            // 2. Control Overlays
            VStack {
                HStack {
                    Picker("Lens", selection: $camera.selectedCameraID) {
                        ForEach(camera.availableCameras, id: \.uniqueID) { cam in
                            Text(cam.localizedName).tag(cam.uniqueID)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .padding(10)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(8)
                    .onChange(of: camera.selectedCameraID) { newID in
                        camera.switchCamera(cameraID: newID)
                    }
                    
                    Spacer()
                    
                    Toggle("Face Tracking", isOn: $camera.isFaceTrackingEnabled)
                        .toggleStyle(SwitchToggleStyle(tint: .green))
                        .padding(10)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(8)
                        .frame(width: 200)
                }
                .padding()
                
                Spacer()
                
                VStack(spacing: 5) {
                    Text("WIRED OBS URL:  http://127.0.0.1:8080")
                        .font(.headline)
                        .foregroundColor(.green)
                    Text("WI-FI OBS URL:  \(camera.getWiFiAddress())")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(10)
                .padding(.bottom, 20)
            }
        }
    }
}

class CameraTracker: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var currentFrame: CGImage?
    @Published var isFaceTrackingEnabled = true
    @Published var availableCameras: [AVCaptureDevice] = []
    @Published var selectedCameraID: String = ""
    
    private var captureSession = AVCaptureSession()
    private var currentFaceRect: CGRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    
    override init() {
        super.init()
        loadCameras()
        startMJPEGServer()
    }
    
    func loadCameras() {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInUltraWideCamera,
            .builtInTelephotoCamera,
            .builtInTrueDepthCamera
        ]
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified)
        
        DispatchQueue.main.async {
            self.availableCameras = discovery.devices
            if let front = self.availableCameras.first(where: { $0.position == .front }) {
                self.selectedCameraID = front.uniqueID
                self.switchCamera(cameraID: front.uniqueID)
            } else if let first = self.availableCameras.first {
                self.selectedCameraID = first.uniqueID
                self.switchCamera(cameraID: first.uniqueID)
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
        
        if let output = captureSession.outputs.first as? AVCaptureVideoDataOutput,
           let connection = output.connection(with: .video) {
            connection.videoOrientation = .landscapeRight
            
            if device.position == .front && connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }
        
        captureSession.commitConfiguration()
        
        if !captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.startRunning()
            }
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
            
            let width = ciImage.extent.width
            let height = ciImage.extent.height
            
            // Fixed Centering Math (Hidden from UI to prevent compiler errors)
            let centerX = (currentFaceRect.origin.x + currentFaceRect.size.width / 2.0) * width
            let centerY = (currentFaceRect.origin.y + currentFaceRect.size.height * 0.45) * height
            
            let cropW = min(width, currentFaceRect.size.width * width * 2.8)
            var cropH = cropW * (9.0/16.0)
            
            if cropH > height {
                cropH = height
            }
            
            var cropX = centerX - (cropW / 2.0)
            var cropY = centerY - (cropH / 2.0)
            
            // Strictly clamp bounds so it never crashes
            cropX = max(0, min(cropX, width - cropW))
            cropY = max(0, min(cropY, height - cropH))
            
            let croppedCI = ciImage.cropped(to: CGRect(x: cropX, y: cropY, width: cropW, height: cropH))
            finalCGImage = CIContext().createCGImage(croppedCI, from: croppedCI.extent)
        } else {
            finalCGImage = CIContext().createCGImage(ciImage, from: ciImage.extent)
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
