import SwiftUI
import AVFoundation
import Vision
import Network
import CoreImage.CIFilterBuiltins
import UIKit

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
            // Background
            Color.black.ignoresSafeArea()
            
            // Video Feed
            if let frame = camera.currentFrame {
                Image(decorative: frame, scale: 1.0, orientation: .up)
                    .resizable().scaledToFit().ignoresSafeArea()
            }
            
            // Raw UI
            if camera.isBlackoutMode {
                Button("WAKE UP SCREEN") { camera.isBlackoutMode = false }
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)
            } else {
                VStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Picker("Lens", selection: $camera.selectedCameraID) {
                            ForEach(camera.availableCameras, id: \.uniqueID) { cam in
                                Text(cam.localizedName).tag(cam.uniqueID)
                            }
                        }
                        
                        Toggle("Face Tracking", isOn: $camera.isFaceTrackingEnabled)
                        Toggle("Lock Exposure", isOn: $camera.isExposureLocked)
                        Toggle("Green Screen BG", isOn: $camera.isGreenScreen)
                        
                        HStack {
                            Text("Zoom")
                            Slider(value: $camera.zoomLevel, in: 1.0...3.0)
                        }
                        
                        Button("Enter OLED Blackout") { camera.isBlackoutMode = true }
                            .padding(.vertical, 5)
                        
                        Text("WIRED: http://127.0.0.1:8080").foregroundColor(.green).font(.caption)
                        Text("WIFI: \(camera.wifiAddress)").foregroundColor(.gray).font(.caption)
                    }
                    .padding()
                    .background(Color.black.opacity(0.85))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .padding()
                }
            }
        }
        .onChange(of: camera.selectedCameraID) { id in camera.switchCamera(cameraID: id) }
        .onChange(of: camera.isExposureLocked) { _ in camera.updateExposureLock() }
    }
}

class CameraTracker: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var currentFrame: CGImage?
    @Published var isFaceTrackingEnabled = true
    @Published var isExposureLocked = false
    @Published var isGreenScreen = false
    @Published var isBlackoutMode = false {
        didSet {
            DispatchQueue.main.async {
                self.originalBrightness = UIScreen.main.brightness
                UIScreen.main.brightness = self.isBlackoutMode ? 0.0 : self.originalBrightness
            }
        }
    }
    
    @Published var zoomLevel: Double = 1.5
    @Published var availableCameras: [AVCaptureDevice] = []
    @Published var selectedCameraID: String = ""
    @Published var wifiAddress: String = "Loading..."
    
    private var captureSession = AVCaptureSession()
    private var currentFaceRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var originalBrightness: CGFloat = 0.5
    
    private var faceRequest = VNDetectFaceRectanglesRequest()
    private var segmentationRequest = VNGeneratePersonSegmentationRequest()
    private var latestFaceRect: CGRect?
    
    override init() {
        super.init()
        segmentationRequest.qualityLevel = .fast
        segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
        
        faceRequest = VNDetectFaceRectanglesRequest { [weak self] req, _ in
            if let results = req.results as? [VNFaceObservation], let face = results.first {
                self?.latestFaceRect = face.boundingBox
            }
        }
        
        wifiAddress = getWiFiAddress()
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
        } catch { }
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
        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let width = ciImage.extent.width
        let height = ciImage.extent.height
        
        var requests: [VNRequest] = []
        if isFaceTrackingEnabled { requests.append(faceRequest) }
        if isGreenScreen { requests.append(segmentationRequest) }
        
        if !requests.isEmpty { try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform(requests) }
        
        if isGreenScreen, let maskPixelBuffer = segmentationRequest.results?.first?.pixelBuffer {
            let maskW = CGFloat(CVPixelBufferGetWidth(maskPixelBuffer))
            let maskH = CGFloat(CVPixelBufferGetHeight(maskPixelBuffer))
            let maskImage = CIImage(cvPixelBuffer: maskPixelBuffer).transformed(by: CGAffineTransform(scaleX: width / maskW, y: height / maskH))
            
            let greenBG = CIImage(color: CIColor.green).cropped(to: ciImage.extent)
            
            let blendFilter = CIFilter.blendWithMask()
            blendFilter.inputImage = ciImage
            blendFilter.backgroundImage = greenBG
            blendFilter.maskImage = maskImage
            ciImage = blendFilter.outputImage ?? ciImage
        }
        
        if isFaceTrackingEnabled, let target = latestFaceRect {
            let ease: CGFloat = 0.1
            currentFaceRect.origin.x += (target.origin.x - currentFaceRect.origin.x) * ease
            currentFaceRect.origin.y += (target.origin.y - currentFaceRect.origin.y) * ease
            currentFaceRect.size.width += (target.size.width - currentFaceRect.size.width) * ease
            currentFaceRect.size.height += (target.size.height - currentFaceRect.size.height) * ease
            
            let centerX = (currentFaceRect.origin.x + currentFaceRect.size.width / 2.0) * width
            let centerY = (currentFaceRect.origin.y + currentFaceRect.size.height * 0.45) * height
            
            let multiplier = CGFloat(max(1.4, 4.2 / zoomLevel))
            var cropW = min(width, currentFaceRect.size.width * width * multiplier)
            var cropH = cropW * 0.5625
            
            if cropH > height { cropH = height; cropW = height * 1.7777 }
            
            let cropX = max(0, min(centerX - (cropW / 2.0), width - cropW))
            let cropY = max(0, min(centerY - (cropH / 2.0), height - cropH))
            
            ciImage = ciImage.cropped(to: CGRect(x: cropX, y: cropY, width: cropW, height: cropH))
                .transformed(by: CGAffineTransform(translationX: -cropX, y: -cropY))
                .transformed(by: CGAffineTransform(scaleX: 1920.0 / cropW, y: 1920.0 / cropW))
        }
        
        guard let outputCG = ciContext.createCGImage(ciImage, from: CGRect(x: 0, y: 0, width: 1920, height: 1080)) else { return }
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
