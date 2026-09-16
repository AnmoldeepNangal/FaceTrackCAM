import SwiftUI
import AVFoundation
import Vision
import Network
import CoreImage.CIFilterBuiltins
import Foundation
import UIKit

@main
struct FaceTrackCamApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - Main UI
struct ContentView: View {
    @StateObject var camera = CameraTracker()
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let frame = camera.currentFrame {
                Image(decorative: frame, scale: 1.0, orientation: .up)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
            }
            
            if camera.isBlackoutMode {
                BlackoutView(camera: camera)
            } else {
                VStack {
                    TopStatusBar(camera: camera)
                    Spacer()
                    BottomControlsBar(camera: camera)
                }
            }
        }
        .preferredColorScheme(.dark)
        // Move hardware triggers out of variables and into explicit listeners
        .onChange(of: camera.isBlackoutMode) { mode in camera.updateScreenBrightness(to: mode) }
        .onChange(of: camera.isExposureLocked) { _ in camera.updateExposureLock() }
    }
}

// MARK: - Sub Views to Prevent Compiler Crashes
struct BlackoutView: View {
    @ObservedObject var camera: CameraTracker
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 10) {
                Image(systemName: "moon.zzz.fill").font(.system(size: 50)).foregroundColor(.gray.opacity(0.3))
                Text("Stream Active. Tap to wake.").foregroundColor(.gray.opacity(0.5))
            }
        }
        .onTapGesture { camera.isBlackoutMode = false }
    }
}

struct TopStatusBar: View {
    @ObservedObject var camera: CameraTracker
    var body: some View {
        HStack {
            Picker("Lens", selection: $camera.selectedCameraID) {
                ForEach(camera.availableCameras, id: \.uniqueID) { cam in
                    Text(cam.localizedName).tag(cam.uniqueID)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            
            Spacer()
            
            HStack(spacing: 12) {
                Image(systemName: camera.thermalIcon)
                    .foregroundColor(camera.thermalColor)
                HStack(spacing: 4) {
                    Text("\(Int(camera.batteryLevel * 100))%").font(.caption.bold())
                    Image(systemName: "battery.100")
                }
                .foregroundColor(camera.batteryLevel < 0.2 ? .red : .primary)
            }
            .padding(.horizontal, 15).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .padding()
    }
}

struct BottomControlsBar: View {
    @ObservedObject var camera: CameraTracker
    var body: some View {
        VStack(spacing: 15) {
            HStack(spacing: 20) {
                ControlToggle(title: "Track", icon: "face.dashed", isOn: $camera.isFaceTrackingEnabled)
                ControlToggle(title: "Lock Exp", icon: "lock.fill", isOn: $camera.isExposureLocked)
                ControlToggle(title: "Blackout", icon: "moon.fill", isOn: $camera.isBlackoutMode)
            }
            
            Divider().background(Color.white.opacity(0.3))
            
            Picker("Background", selection: $camera.bgMode) {
                Text("Normal").tag(0)
                Text("Blur").tag(1)
                Text("Green").tag(2)
            }
            .pickerStyle(SegmentedPickerStyle())
            
            if camera.isFaceTrackingEnabled {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Slider(value: $camera.zoomLevel, in: 1.0...3.0, step: 0.1).accentColor(.white)
                    Text("\(String(format: "%.1fx", camera.zoomLevel))").font(.caption.bold())
                }
            }
            
            if camera.bgMode == 1 {
                HStack {
                    Image(systemName: "drop.fill")
                    Slider(value: $camera.blurRadius, in: 5.0...40.0, step: 1.0).accentColor(.white)
                }
            }
            
            HStack {
                Text("Wired: 127.0.0.1:8080").font(.caption2.bold()).foregroundColor(.green)
                Spacer()
                Text("Wi-Fi: \(camera.wifiAddress)").font(.caption2.bold()).foregroundColor(.gray)
            }
            .padding(.top, 5)
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .padding()
    }
}

struct ControlToggle: View {
    var title: String
    var icon: String
    @Binding var isOn: Bool
    var body: some View {
        Button(action: { isOn.toggle() }) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title2)
                Text(title).font(.caption2.bold())
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(isOn ? Color.white : Color.clear)
            .foregroundColor(isOn ? .black : .white)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1))
        }
    }
}

// MARK: - Camera & Streaming Engine
class CameraTracker: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var currentFrame: CGImage?
    @Published var isFaceTrackingEnabled = true
    @Published var isExposureLocked = false
    @Published var isBlackoutMode = false
    
    // bgMode: 0 = Normal, 1 = Blur, 2 = Green Screen
    @Published var bgMode: Int = 0
    @Published var zoomLevel: Double = 1.5
    @Published var blurRadius: Double = 15.0
    
    @Published var availableCameras: [AVCaptureDevice] = []
    @Published var selectedCameraID: String = ""
    @Published var batteryLevel: Float = 1.0
    @Published var wifiAddress: String = "Loading..."
    
    // Thermal outputs for UI mapping
    @Published var thermalIcon: String = "thermometer.sun"
    @Published var thermalColor: Color = .green
    
    private var captureSession = AVCaptureSession()
    private var currentFaceRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var originalBrightness: CGFloat = 0.5
    
    private lazy var faceRequest: VNDetectFaceRectanglesRequest = {
        return VNDetectFaceRectanglesRequest { [weak self] req, _ in
            if let results = req.results as? [VNFaceObservation], let face = results.first {
                self?.latestFaceRect = face.boundingBox
            }
        }
    }()
    
    private var segmentationRequest = VNGeneratePersonSegmentationRequest()
    private var latestFaceRect: CGRect?
    
    override init() {
        super.init()
        segmentationRequest.qualityLevel = .fast
        segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
        
        setupSystemMonitors()
        loadCameras()
        startMJPEGServer()
    }
    
    func setupSystemMonitors() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        updateDeviceStats()
        
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateDeviceStats()
        }
    }
    
    func updateDeviceStats() {
        DispatchQueue.main.async {
            self.batteryLevel = UIDevice.current.batteryLevel
            self.wifiAddress = self.getWiFiAddress()
            
            switch ProcessInfo.processInfo.thermalState {
            case .nominal:
                self.thermalIcon = "thermometer.sun"
                self.thermalColor = .green
            case .fair:
                self.thermalIcon = "thermometer.sun.fill"
                self.thermalColor = .yellow
            case .serious:
                self.thermalIcon = "thermometer.high"
                self.thermalColor = .orange
            case .critical:
                self.thermalIcon = "flame.fill"
                self.thermalColor = .red
            @unknown default:
                self.thermalIcon = "thermometer"
                self.thermalColor = .white
            }
        }
    }
    
    func updateScreenBrightness(to mode: Bool) {
        DispatchQueue.main.async {
            if mode {
                self.originalBrightness = UIScreen.main.brightness
                UIScreen.main.brightness = 0.0
            } else {
                UIScreen.main.brightness = self.originalBrightness
            }
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
        } catch {}
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
        if bgMode != 0 { requests.append(segmentationRequest) }
        
        if !requests.isEmpty {
            try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform(requests)
        }
        
        if bgMode != 0, let maskPixelBuffer = segmentationRequest.results?.first?.pixelBuffer {
            let maskW = CGFloat(CVPixelBufferGetWidth(maskPixelBuffer))
            let maskH = CGFloat(CVPixelBufferGetHeight(maskPixelBuffer))
            let scaleTransform = CGAffineTransform(scaleX: width / maskW, y: height / maskH)
            let maskImage = CIImage(cvPixelBuffer: maskPixelBuffer).transformed(by: scaleTransform)
            
            let bgImage: CIImage
            if bgMode == 1 {
                let blurFilter = CIFilter.gaussianBlur()
                blurFilter.inputImage = ciImage
                blurFilter.radius = Float(blurRadius)
                bgImage = blurFilter.outputImage?.cropped(to: ciImage.extent) ?? ciImage
            } else { 
                bgImage = CIImage(color: CIColor.green).cropped(to: ciImage.extent)
            }
            
            let blendFilter = CIFilter.blendWithMask()
            blendFilter.inputImage = ciImage
            blendFilter.backgroundImage = bgImage
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
            var cropH = cropW * 0.5625 // 9:16 ratio
            
            if cropH > height { cropH = height; cropW = height * 1.7777 } // 16:9 ratio
            
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
