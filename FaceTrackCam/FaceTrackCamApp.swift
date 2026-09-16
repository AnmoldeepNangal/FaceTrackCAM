import SwiftUI
import AVFoundation
import Vision
import Network
import PhotosUI
import CoreImage.CIFilterBuiltins
import UIKit

@main
struct FaceTrackCamApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Models

enum BackgroundMode: String, CaseIterable, Identifiable {
    case off = "OFF"
    case portrait = "PORTRAIT"
    case custom = "CUSTOM"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .off: return "circle.slash"
        case .portrait: return "person.crop.rectangle"
        case .custom: return "photo"
        }
    }
}

// MARK: - Main UI

struct ContentView: View {
    @StateObject private var camera = CameraTracker()

    @State private var isBlackoutMode = false
    @State private var previousBrightness: CGFloat = 0.5
    @State private var backgroundPickerItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            // The preview is the only layer allowed to extend under
            // the Dynamic Island / Home Indicator.
            CameraPreviewView(image: camera.currentFrame)
                .ignoresSafeArea()

            if isBlackoutMode {
                blackoutView
            } else {
                controls
            }
        }
        .background(Color.black)
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
        .onDisappear {
            camera.stop()
        }
    }

    // MARK: Top + Bottom Control Layout

    private var controls: some View {
        VStack(spacing: 0) {
            topPanel

            Spacer(minLength: 0)

            bottomPanel
        }
        // Deliberately NOT using ignoresSafeArea here.
        // SwiftUI keeps the controls inside the safe areas while
        // the camera preview remains full screen behind them.
    }

    private var topPanel: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center) {
                batteryStatus

                Spacer(minLength: 16)

                networkAddress

                Spacer(minLength: 16)

                Button {
                    previousBrightness = UIScreen.main.brightness
                    UIScreen.main.brightness = 0
                    isBlackoutMode = true
                } label: {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.10))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.96), .black.opacity(0.78), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    private var batteryStatus: some View {
        HStack(spacing: 7) {
            Image(systemName: batteryIcon)
                .font(.system(size: 17, weight: .medium))

            Text("\(Int(max(0, camera.batteryLevel) * 100))%")
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .frame(minWidth: 72, alignment: .leading)
    }

    private var networkAddress: some View {
        VStack(spacing: 1) {
            Text("DROIDCAM SERVER")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.42))

            Text(camera.getWiFiAddress())
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.yellow)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: 250)
    }

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            // Zoom
            zoomControl
                .padding(.bottom, 18)

            // Background controls
            backgroundControl
                .padding(.bottom, 22)

            // Camera / tracking / lock
            actionControls
                .padding(.bottom, 18)

            // Small status row
            statusRow
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .background(
            LinearGradient(
                colors: [
                    .clear,
                    .black.opacity(0.78),
                    .black.opacity(0.96),
                    .black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var zoomControl: some View {
        VStack(spacing: 8) {
            HStack {
                Label("ZOOM", systemImage: "plus.magnifyingglass")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.55))

                Spacer()

                Text(String(format: "%.1fx", camera.zoomIntensity))
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(.yellow)
            }

            Slider(value: $camera.zoomIntensity, in: 1.0...4.0, step: 0.1)
                .tint(.yellow)
        }
    }

    private var backgroundControl: some View {
        VStack(spacing: 9) {
            HStack {
                Label("BACKGROUND", systemImage: "person.crop.rectangle")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.55))

                Spacer()

                if camera.backgroundMode == .custom {
                    PhotosPicker(
                        selection: $backgroundPickerItem,
                        matching: .images,
                        photoLibrary: .shared
                    ) {
                        HStack(spacing: 6) {
                            Image(systemName: camera.hasCustomBackground
                                  ? "photo.fill"
                                  : "photo.badge.plus")
                            Text(camera.hasCustomBackground ? "CHANGE" : "ADD")
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.yellow)
                    }
                    .buttonStyle(.plain)
                    .onChange(of: backgroundPickerItem) { _, newItem in
                        guard let newItem else { return }

                        Task {
                            if let data = try? await newItem.loadTransferable(type: Data.self),
                               let image = UIImage(data: data) {
                                camera.setCustomBackground(uiImage: image)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 4) {
                ForEach(BackgroundMode.allCases) { mode in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            camera.backgroundMode = mode
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 11, weight: .semibold))

                            Text(mode.rawValue)
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(
                            camera.backgroundMode == mode
                            ? .black
                            : .white.opacity(0.72)
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            camera.backgroundMode == mode
                            ? Color.yellow
                            : Color.white.opacity(0.09)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var actionControls: some View {
        HStack(spacing: 0) {
            // Lens
            Menu {
                Picker("Lens", selection: $camera.selectedCameraID) {
                    ForEach(camera.availableCameras, id: \.uniqueID) { device in
                        Text(device.localizedName)
                            .tag(device.uniqueID)
                    }
                }
            } label: {
                controlButton(
                    icon: "camera.aperture",
                    title: "LENS",
                    active: false
                )
            }
            .onChange(of: camera.selectedCameraID) { _, newID in
                camera.switchCamera(cameraID: newID)
            }

            Spacer()

            // Main tracking control
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    camera.isFaceTrackingEnabled.toggle()
                }
            } label: {
                VStack(spacing: 5) {
                    Image(
                        systemName: camera.isFaceTrackingEnabled
                        ? "person.and.background.dotted"
                        : "person.fill"
                    )
                    .font(.system(size: 27, weight: .medium))

                    Text(camera.isFaceTrackingEnabled ? "TRACKING" : "TRACK OFF")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.8)
                }
                .foregroundStyle(camera.isFaceTrackingEnabled ? .black : .white)
                .frame(width: 88, height: 88)
                .background(
                    camera.isFaceTrackingEnabled
                    ? Color.yellow
                    : Color.white.opacity(0.11)
                )
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            camera.isFaceTrackingEnabled
                            ? Color.white
                            : Color.white.opacity(0.35),
                            lineWidth: 2
                        )
                )
            }
            .buttonStyle(.plain)

            Spacer()

            // Exposure / focus lock
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    camera.isExposureLocked.toggle()
                }
                camera.toggleExposureLock(lock: camera.isExposureLocked)
            } label: {
                controlButton(
                    icon: camera.isExposureLocked
                        ? "lock.fill"
                        : "lock.open.fill",
                    title: camera.isExposureLocked ? "LOCKED" : "AE / AF",
                    active: camera.isExposureLocked
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func controlButton(
        icon: String,
        title: String,
        active: Bool
    ) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))

            Text(title)
                .font(.system(size: 8, weight: .bold))
                .tracking(0.8)
        }
        .foregroundStyle(active ? .yellow : .white)
        .frame(width: 72, height: 72)
        .background(
            active
            ? Color.yellow.opacity(0.12)
            : Color.white.opacity(0.10)
        )
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(
                    active ? Color.yellow.opacity(0.55) : Color.white.opacity(0.12),
                    lineWidth: 1
                )
        )
    }

    private var statusRow: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(camera.isServerRunning ? Color.green : Color.red)
                .frame(width: 7, height: 7)

            Text(camera.isServerRunning ? "SERVER ONLINE" : "SERVER OFFLINE")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.48))

            Text("•")
                .foregroundStyle(.white.opacity(0.22))

            Text("THERMAL \(camera.thermalString.uppercased())")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(camera.thermalColor.opacity(0.72))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    private var batteryIcon: String {
        let level = camera.batteryLevel

        switch level {
        case ..<0.1:
            return "battery.0percent"
        case ..<0.25:
            return "battery.25percent"
        case ..<0.5:
            return "battery.50percent"
        case ..<0.75:
            return "battery.75percent"
        default:
            return "battery.100percent"
        }
    }

    private var blackoutView: some View {
        Color.black
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 36))

                    Text("BLACKOUT MODE")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(1.2)

                    Text("Camera and server remain active")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .foregroundStyle(.white.opacity(0.55))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                UIScreen.main.brightness = previousBrightness
                isBlackoutMode = false
            }
    }
}

// MARK: - Camera Preview

struct CameraPreviewView: View {
    let image: CGImage?

    var body: some View {
        ZStack {
            Color.black

            if let image {
                Image(
                    decorative: image,
                    scale: 1.0,
                    orientation: .up
                )
                .resizable()
                .aspectRatio(contentMode: .fit)
            } else {
                ProgressView()
                    .tint(.white.opacity(0.65))
            }
        }
    }
}

// MARK: - Camera Engine

final class CameraTracker: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var currentFrame: CGImage?
    @Published var isFaceTrackingEnabled = true
    @Published var backgroundMode: BackgroundMode = .off
    @Published var isExposureLocked = false
    @Published var zoomIntensity: CGFloat = 2.8

    @Published var availableCameras: [AVCaptureDevice] = []
    @Published var selectedCameraID = ""

    @Published var batteryLevel: Float = 1.0
    @Published var thermalString = "Normal"
    @Published var thermalColor: Color = .green
    @Published private(set) var isServerRunning = false

    var hasCustomBackground: Bool {
        customBackgroundImage != nil
    }

    private let captureSession = AVCaptureSession()
    private let videoQueue = DispatchQueue(
        label: "com.facetrackcam.videoQueue",
        qos: .userInitiated
    )

    private let context = CIContext()
    private let segmentationRequest = VNGeneratePersonSegmentationRequest()

    private var customBackgroundImage: CIImage?
    private var currentFaceRect = CGRect(
        x: 0.25,
        y: 0.25,
        width: 0.5,
        height: 0.5
    )

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var monitorTimer: Timer?

    override init() {
        super.init()

        segmentationRequest.qualityLevel = .balanced
        segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8

        loadCameras()
        startMJPEGServer()
        startHardwareMonitor()
    }

    deinit {
        stop()
    }

    // MARK: Lifecycle

    func stop() {
        monitorTimer?.invalidate()
        monitorTimer = nil

        listener?.cancel()
        listener = nil

        connections.forEach { $0.cancel() }
        connections.removeAll()

        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }

    // MARK: Hardware

    private func startHardwareMonitor() {
        monitorTimer = Timer.scheduledTimer(
            withTimeInterval: 5,
            repeats: true
        ) { [weak self] _ in
            self?.updateHardwareState()
        }

        updateHardwareState()
    }

    private func updateHardwareState() {
        let level = UIDevice.current.batteryLevel
        batteryLevel = level >= 0 ? level : 0

        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            thermalString = "Normal"
            thermalColor = .green
        case .fair:
            thermalString = "Warm"
            thermalColor = .yellow
        case .serious:
            thermalString = "Hot"
            thermalColor = .orange
        case .critical:
            thermalString = "Critical"
            thermalColor = .red
        @unknown default:
            thermalString = "Unknown"
            thermalColor = .gray
        }
    }

    // MARK: Camera Discovery

    func loadCameras() {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInUltraWideCamera,
            .builtInTelephotoCamera,
            .builtInTrueDepthCamera
        ]

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: .unspecified
        )

        let devices = discovery.devices

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.availableCameras = devices

            let preferred =
                devices.first(where: { $0.position == .front }) ??
                devices.first

            if let preferred {
                self.selectedCameraID = preferred.uniqueID
                self.switchCamera(cameraID: preferred.uniqueID)
            }
        }
    }

    func switchCamera(cameraID: String) {
        guard let device = availableCameras.first(where: {
            $0.uniqueID == cameraID
        }) else {
            return
        }

        captureSession.beginConfiguration()
        captureSession.sessionPreset = .hd1920x1080

        captureSession.inputs.forEach {
            captureSession.removeInput($0)
        }

        if let input = try? AVCaptureDeviceInput(device: device),
           captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        if captureSession.outputs.isEmpty {
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_32BGRA
            ]
            output.setSampleBufferDelegate(self, queue: videoQueue)

            if captureSession.canAddOutput(output) {
                captureSession.addOutput(output)
            }
        }

        if let output = captureSession.outputs.first as? AVCaptureVideoDataOutput,
           let connection = output.connection(with: .video) {

            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = device.position == .front
            }

            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
        }

        captureSession.commitConfiguration()

        if !captureSession.isRunning {
            videoQueue.async { [weak self] in
                self?.captureSession.startRunning()
            }
        }
    }

    // MARK: Background Selection

    func setCustomBackground(uiImage: UIImage) {
        guard let image = CIImage(
            image: uiImage,
            options: [.applyOrientationProperty: true]
        ) else {
            return
        }

        videoQueue.async { [weak self] in
            self?.customBackgroundImage = image
        }
    }

    private func scaledToFill(
        image: CIImage,
        targetSize: CGSize
    ) -> CIImage {
        let extent = image.extent

        guard extent.width > 0,
              extent.height > 0,
              targetSize.width > 0,
              targetSize.height > 0 else {
            return image
        }

        let scale = max(
            targetSize.width / extent.width,
            targetSize.height / extent.height
        )

        let scaled = image.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )

        let scaledExtent = scaled.extent

        let cropX =
            scaledExtent.origin.x +
            (scaledExtent.width - targetSize.width) / 2

        let cropY =
            scaledExtent.origin.y +
            (scaledExtent.height - targetSize.height) / 2

        let cropRect = CGRect(
            x: cropX,
            y: cropY,
            width: targetSize.width,
            height: targetSize.height
        )

        return scaled
            .cropped(to: cropRect)
            .transformed(
                by: CGAffineTransform(
                    translationX: -cropRect.origin.x,
                    y: -cropRect.origin.y
                )
            )
    }

    // MARK: Exposure / Focus

    func toggleExposureLock(lock: Bool) {
        guard let device = captureSession.inputs
            .compactMap({ $0 as? AVCaptureDeviceInput })
            .first?
            .device else {
            return
        }

        do {
            try device.lockForConfiguration()

            if lock {
                if device.isExposureModeSupported(.locked) {
                    device.exposureMode = .locked
                }

                if device.isWhiteBalanceModeSupported(.locked) {
                    device.whiteBalanceMode = .locked
                }

                if device.isFocusModeSupported(.locked) {
                    device.focusMode = .locked
                }
            } else {
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }

                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }

                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
            }

            device.unlockForConfiguration()
        } catch {
            print("Camera configuration error: \(error)")
        }
    }

    // MARK: Video Processing

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        var image = CIImage(cvPixelBuffer: pixelBuffer)

        if backgroundMode != .off {
            image = applyBackground(to: image, pixelBuffer: pixelBuffer)
        }

        let finalImage: CGImage?

        if isFaceTrackingEnabled {
            updateFaceTracking(with: image)

            let width = image.extent.width
            let height = image.extent.height

            let faceX = currentFaceRect.origin.x * width
            let faceY =
                (1 - currentFaceRect.origin.y - currentFaceRect.height) *
                height

            let faceW = currentFaceRect.width * width
            let faceH = currentFaceRect.height * height

            let feedRatio = height / width

            let cropW = min(faceW * zoomIntensity, width)
            let cropH = min(cropW * feedRatio, height)

            let centerX = faceX + faceW / 2
            let centerY = faceY + faceH / 2

            let cropX = max(
                0,
                min(centerX - cropW / 2, width - cropW)
            )

            let cropY = max(
                0,
                min(centerY - cropH / 2, height - cropH)
            )

            let cropRect = CGRect(
                x: cropX,
                y: cropY,
                width: cropW,
                height: cropH
            )

            let cropped = image.cropped(to: cropRect)
            finalImage = context.createCGImage(
                cropped,
                from: cropped.extent
            )
        } else {
            finalImage = context.createCGImage(
                image,
                from: image.extent
            )
        }

        guard let outputCG = finalImage else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.currentFrame = outputCG
        }

        sendJPEG(outputCG)
    }

    private func applyBackground(
        to image: CIImage,
        pixelBuffer: CVPixelBuffer
    ) -> CIImage {
        try? VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            options: [:]
        ).perform([segmentationRequest])

        guard let maskPixelBuffer =
                segmentationRequest.results?.first?.pixelBuffer else {
            return image
        }

        let maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)

        let scaleX =
            image.extent.width / maskImage.extent.width

        let scaleY =
            image.extent.height / maskImage.extent.height

        let scaledMask = maskImage.transformed(
            by: CGAffineTransform(scaleX: scaleX, y: scaleY)
        )

        let background: CIImage?

        switch backgroundMode {
        case .off:
            background = nil

        case .portrait:
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = image
            blur.radius = 15
            background = blur.outputImage?.cropped(to: image.extent)

        case .custom:
            if let customBackgroundImage {
                background = scaledToFill(
                    image: customBackgroundImage,
                    targetSize: image.extent.size
                )
            } else {
                background = nil
            }
        }

        guard let background else {
            return image
        }

        let blend = CIFilter.blendWithMask()
        blend.inputImage = image
        blend.backgroundImage = background
        blend.maskImage = scaledMask

        return blend.outputImage?.cropped(to: image.extent) ?? image
    }

    private func updateFaceTracking(with image: CIImage) {
        let request = VNDetectFaceRectanglesRequest()

        do {
            try VNImageRequestHandler(
                ciImage: image,
                options: [:]
            ).perform([request])

            guard let face = request.results?.first else {
                return
            }

            let target = face.boundingBox

            // Exponential smoothing keeps the crop stable instead
            // of jumping with every Vision result.
            let smoothing: CGFloat = 0.10

            currentFaceRect.origin.x +=
                (target.origin.x - currentFaceRect.origin.x) * smoothing

            currentFaceRect.origin.y +=
                (target.origin.y - currentFaceRect.origin.y) * smoothing

            currentFaceRect.size.width +=
                (target.size.width - currentFaceRect.size.width) * smoothing

            currentFaceRect.size.height +=
                (target.size.height - currentFaceRect.size.height) * smoothing

        } catch {
            // Ignore individual Vision failures; the next frame will retry.
        }
    }

    // MARK: MJPEG Server

    private func startMJPEGServer() {
        guard let listener = try? NWListener(
            using: .tcp,
            on: 8080
        ) else {
            DispatchQueue.main.async {
                self.isServerRunning = false
            }
            return
        }

        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isServerRunning = true
                case .failed, .cancelled:
                    self?.isServerRunning = false
                default:
                    break
                }
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }

            connection.stateUpdateHandler = { [weak self, weak connection] state in
                if case .cancelled = state {
                    self?.connections.removeAll {
                        $0 === connection
                    }
                }
            }

            connection.start(queue: .global(qos: .utility))

            let header =
                "HTTP/1.1 200 OK\r\n" +
                "Cache-Control: no-cache\r\n" +
                "Pragma: no-cache\r\n" +
                "Connection: close\r\n" +
                "Content-Type: multipart/x-mixed-replace; boundary=frame\r\n\r\n"

            connection.send(
                content: header.data(using: .utf8),
                completion: .contentProcessed { _ in }
            )

            self.videoQueue.async {
                self.connections.append(connection)
            }
        }

        listener.start(queue: .global(qos: .utility))
    }

    private func sendJPEG(_ image: CGImage) {
        let uiImage = UIImage(cgImage: image)

        guard let jpeg = uiImage.jpegData(compressionQuality: 0.60) else {
            return
        }

        let header =
            "--frame\r\n" +
            "Content-Type: image/jpeg\r\n" +
            "Content-Length: \(jpeg.count)\r\n\r\n"

        let data =
            (header.data(using: .utf8) ?? Data()) +
            jpeg +
            Data("\r\n".utf8)

        connections.forEach { connection in
            connection.send(
                content: data,
                completion: .contentProcessed { _ in }
            )
        }
    }

    // MARK: Network Address

    func getWiFiAddress() -> String {
        var address = "NOT CONNECTED"

        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else {
            return address
        }

        defer {
            freeifaddrs(ifaddr)
        }

        var pointer = ifaddr

        while pointer != nil {
            defer {
                pointer = pointer?.pointee.ifa_next
            }

            guard let interface = pointer?.pointee,
                  let socketAddress = interface.ifa_addr else {
                continue
            }

            guard socketAddress.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            guard String(cString: interface.ifa_name) == "en0" else {
                continue
            }

            var hostname = [CChar](
                repeating: 0,
                count: Int(NI_MAXHOST)
            )

            getnameinfo(
                socketAddress,
                socklen_t(socketAddress.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            address = "http://\(String(cString: hostname)):8080"
            break
        }

        return address
    }
}
