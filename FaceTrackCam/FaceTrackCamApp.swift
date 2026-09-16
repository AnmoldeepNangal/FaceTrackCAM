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
            if let frame = camera.currentFrame {
                Image(decorative: frame, scale: 1.0, orientation: .up)
                    .resizable()
                    .scaledToFit()
            } else {
                Text("Starting Camera & Server on Port 8080...")
                    .foregroundColor(.white)
            }
        }
    }
}

class CameraTracker: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var currentFrame: CGImage?
    private var captureSession = AVCaptureSession()
    private var currentFaceRect: CGRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    
    override init() {
        super.init()
        setupCamera()
        startMJPEGServer()
    }
    
    func setupCamera() {
        captureSession.sessionPreset = .hd1920x1080
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        
        if captureSession.canAddInput(input) { captureSession.addInput(input) }
        
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if captureSession.canAddOutput(output) { captureSession.addOutput(output) }
        
        // Force landscape orientation for 16:9 streaming
        if let connection = output.connection(with: .video) {
            connection.videoOrientation = .landscapeRight
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
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
        
        // 1. Hardware Face Detection
        let request = VNDetectFaceRectanglesRequest { [weak self] req, _ in
            guard let self = self, let results = req.results as? [VNFaceObservation], let face = results.first else { return }
            
            // Smooth Camera Panning (Lerp formula)
            let target = face.boundingBox
            self.currentFaceRect.origin.x += (target.origin.x - self.currentFaceRect.origin.x) * 0.08
            self.currentFaceRect.origin.y += (target.origin.y - self.currentFaceRect.origin.y) * 0.08
            self.currentFaceRect.size.width += (target.size.width - self.currentFaceRect.size.width) * 0.08
            self.currentFaceRect.size.height += (target.size.height - self.currentFaceRect.size.height) * 0.08
        }
        try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([request])
        
        // 2. Crop & Frame
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let width = ciImage.extent.width
        let height = ciImage.extent.height
        
        let faceX = currentFaceRect.origin.x * width
        let faceY = (1 - currentFaceRect.origin.y - currentFaceRect.size.height) * height
        let faceW = currentFaceRect.size.width * width
        let faceH = currentFaceRect.size.height * height
        
        let cropW = faceW * 2.5 // Adjust this multiplier to zoom in or out
        let cropH = cropW * (9.0/16.0) 
        let cropX = (faceX + faceW/2) - (cropW / 2)
        let cropY = (faceY + faceH/2) - (cropH / 2)
        
        let croppedCI = ciImage.cropped(to: CGRect(x: cropX, y: cropY, width: cropW, height: cropH))
        guard let cgImage = CIContext().createCGImage(croppedCI, from: croppedCI.extent) else { return }
        
        DispatchQueue.main.async { self.currentFrame = cgImage }
        
        // 3. Broadcast Stream to Windows
        let uiImage = UIImage(cgImage: cgImage)
        if let jpeg = uiImage.jpegData(compressionQuality: 0.6) {
            let header = "--frame\r\nContent-Type: image/jpeg\r\nContent-Length: \(jpeg.count)\r\n\r\n"
            let data = header.data(using: .utf8)! + jpeg + "\r\n".data(using: .utf8)!
            
            self.connections.forEach { conn in
                conn.send(content: data, completion: .contentProcessed({ _ in }))
            }
        }
    }
}
