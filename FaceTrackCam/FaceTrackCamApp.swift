import SwiftUI
import UIKit
import AVFoundation
import Vision
import Network
import PhotosUI
import CoreImage
import CoreImage.CIFilterBuiltins
import Darwin

// ============================================================
// MARK: - APP
// ============================================================

@main
struct FaceTrackCamApp: App {

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

// ============================================================
// MARK: - BACKGROUND MODE
// ============================================================

enum BackgroundMode: String, CaseIterable {
    case off = "OFF"
    case portrait = "PORTRAIT"
    case custom = "CUSTOM"
}

// ============================================================
// MARK: - MAIN CONTENT VIEW
// ============================================================

struct ContentView: View {

    @StateObject private var camera = CameraTracker()

    @State private var isBlackoutMode = false
    @State private var previousBrightness: CGFloat = 0.5
    @State private var backgroundPickerItem: PhotosPickerItem?

    var body: some View {

        GeometryReader { geometry in

            ZStack {

                Color.black
                    .ignoresSafeArea()

                if isBlackoutMode {

                    // ====================================================
                    // BLACKOUT MODE
                    // ====================================================

                    Color.black
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            wakeFromBlackout()
                        }

                    VStack(spacing: 12) {

                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 42))
                            .foregroundColor(.gray)

                        Text("BLACKOUT MODE")
                            .font(
                                .system(
                                    size: 16,
                                    weight: .semibold
                                )
                            )
                            .foregroundColor(.gray)

                        Text("Tap anywhere to wake")
                            .font(.system(size: 13))
                            .foregroundColor(.gray.opacity(0.7))
                    }

                } else {

                    // ====================================================
                    // DEDICATED CAMERA + LETTERBOX CONTROLS
                    // ====================================================

                    VStack(spacing: 0) {

                        // TOP BAR (In top black letterbox band)
                        topControls
                            .padding(.top, geometry.safeAreaInsets.top + 6)
                            .padding(.bottom, 6)
                            .frame(maxWidth: .infinity)
                            .background(Color.black)

                        Spacer(minLength: 0)

                        // CAMERA PREVIEW (Preserved aspect ratio, completely unblocked)
                        if let frame = camera.currentFrame {

                            Image(
                                decorative: frame,
                                scale: 1.0,
                                orientation: .up
                            )
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: geometry.size.width)
                            .clipped()

                        } else {

                            Color.black
                                .aspectRatio(9/16, contentMode: .fit)
                                .overlay(
                                    ProgressView()
                                        .progressViewStyle(
                                            CircularProgressViewStyle(tint: .white)
                                        )
                                )
                        }

                        Spacer(minLength: 0)

                        // BOTTOM CONTROLS (In bottom black letterbox band)
                        bottomControls
                            .padding(
                                .bottom,
                                geometry.safeAreaInsets.bottom > 0
                                ? geometry.safeAreaInsets.bottom
                                : 10
                            )
                            .frame(maxWidth: .infinity)
                            .background(Color.black)
                    }
                    .ignoresSafeArea()
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {

            UIDevice.current.isBatteryMonitoringEnabled = true
            camera.updateBattery()
        }
    }

    // ============================================================
    // MARK: - TOP CONTROLS
    // ============================================================

    private var topControls: some View {

        HStack(spacing: 12) {

            // --------------------------------------------------------
            // BATTERY
            // --------------------------------------------------------

            HStack(spacing: 5) {

                Image(
                    systemName:
                        camera.batteryLevel > 0.20
                        ? "battery.100"
                        : "battery.25"
                )

                Text(
                    "\(Int(camera.batteryLevel * 100))%"
                )
            }
            .font(
                .system(
                    size: 14,
                    weight: .semibold
                )
            )
            .foregroundColor(.white)

            Spacer()

            // --------------------------------------------------------
            // SERVER ADDRESS
            // --------------------------------------------------------

            Text(camera.getWiFiAddress())
                .font(
                    .system(
                        size: 13,
                        weight: .bold,
                        design: .monospaced
                    )
                )
                .foregroundColor(.yellow)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Spacer()

            // --------------------------------------------------------
            // BLACKOUT
            // --------------------------------------------------------

            Button {

                enterBlackout()

            } label: {

                Image(systemName: "moon.fill")
                    .font(
                        .system(
                            size: 18,
                            weight: .medium
                        )
                    )
                    .foregroundColor(.white)
                    .frame(
                        width: 42,
                        height: 42
                    )
                    .background(
                        Color.white.opacity(0.15)
                    )
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 18)
    }

    // ============================================================
    // MARK: - BOTTOM CONTROLS
    // ============================================================

    private var bottomControls: some View {

        VStack(spacing: 12) {

            // ========================================================
            // ZOOM
            // ========================================================

            HStack(spacing: 10) {

                Text(
                    String(
                        format: "%.1fx",
                        camera.zoomIntensity
                    )
                )
                .font(
                    .system(
                        size: 14,
                        weight: .bold
                    )
                )
                .foregroundColor(.yellow)
                .frame(
                    width: 42,
                    alignment: .leading
                )

                Slider(
                    value: $camera.zoomIntensity,
                    in: 1.0...4.0,
                    step: 0.1
                )
                .tint(.yellow)

                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.75))
            }
            .padding(.horizontal, 22)

            // ========================================================
            // BACKGROUND CONTROLS
            // ========================================================

            HStack(spacing: 7) {

                ForEach(
                    BackgroundMode.allCases,
                    id: \.self
                ) { mode in

                    Button {

                        withAnimation(
                            .easeOut(duration: 0.15)
                        ) {
                            camera.backgroundMode = mode
                        }

                    } label: {

                        Text(mode.rawValue)
                            .font(
                                .system(
                                    size: 12,
                                    weight: .bold
                                )
                            )
                            .foregroundColor(
                                camera.backgroundMode == mode
                                ? .black
                                : .white.opacity(0.80)
                            )
                            .frame(
                                maxWidth: .infinity
                            )
                            .frame(height: 38)
                            .background(
                                camera.backgroundMode == mode
                                ? Color.yellow
                                : Color.white.opacity(0.13)
                            )
                            .clipShape(Capsule())
                    }
                }

                // ----------------------------------------------------
                // CUSTOM IMAGE
                // ----------------------------------------------------

                if camera.backgroundMode == .custom {

                    PhotosPicker(
                        selection: $backgroundPickerItem,
                        matching: .images
                    ) {

                        Image(
                            systemName:
                                camera.hasCustomBackground
                                ? "photo.fill"
                                : "photo.badge.plus"
                        )
                        .font(
                            .system(
                                size: 17,
                                weight: .semibold
                            )
                        )
                        .foregroundColor(
                            camera.hasCustomBackground
                            ? .yellow
                            : .white
                        )
                        .frame(
                            width: 44,
                            height: 38
                        )
                        .background(
                            Color.white.opacity(0.13)
                        )
                        .clipShape(Capsule())
                    }
                    .onChange(
                        of: backgroundPickerItem
                    ) { _, item in

                        guard let item else {
                            return
                        }

                        Task {

                            if let data =
                                try? await item.loadTransferable(
                                    type: Data.self
                                ),
                               let image =
                                UIImage(data: data) {

                                camera.setCustomBackground(
                                    uiImage: image
                                )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)

            // ========================================================
            // MAIN ACTION BUTTONS
            // ========================================================

            HStack {

                // ----------------------------------------------------
                // CAMERA / LENS
                // ----------------------------------------------------

                Menu {

                    Picker(
                        "Camera",
                        selection: $camera.selectedCameraID
                    ) {

                        ForEach(
                            camera.availableCameras,
                            id: \.uniqueID
                        ) { device in

                            Text(
                                device.localizedName
                            )
                            .tag(device.uniqueID)
                        }
                    }

                } label: {

                    Image(
                        systemName: "camera.aperture"
                    )
                    .font(
                        .system(
                            size: 23,
                            weight: .medium
                        )
                    )
                    .foregroundColor(.white)
                    .frame(
                        width: 54,
                        height: 54
                    )
                    .background(
                        Color.white.opacity(0.12)
                    )
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                Color.white.opacity(0.20),
                                lineWidth: 1
                            )
                    )
                }
                .onChange(
                    of: camera.selectedCameraID
                ) { _, newID in

                    camera.switchCamera(
                        cameraID: newID
                    )
                }

                Spacer()

                // ----------------------------------------------------
                // FACE TRACKING
                // ----------------------------------------------------

                Button {

                    withAnimation(
                        .spring(
                            response: 0.25,
                            dampingFraction: 0.75
                        )
                    ) {

                        camera.isFaceTrackingEnabled.toggle()
                    }

                } label: {

                    Image(
                        systemName:
                            camera.isFaceTrackingEnabled
                            ? "person.and.background.dotted"
                            : "person.fill"
                    )
                    .font(
                        .system(
                            size: 26,
                            weight: .medium
                        )
                    )
                    .foregroundColor(
                        camera.isFaceTrackingEnabled
                        ? .black
                        : .white
                    )
                    .frame(
                        width: 70,
                        height: 70
                    )
                    .background(
                        camera.isFaceTrackingEnabled
                        ? Color.yellow
                        : Color.white.opacity(0.15)
                    )
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                Color.white,
                                lineWidth: 2.5
                            )
                    )
                    .shadow(
                        color: .black.opacity(0.45),
                        radius: 8
                    )
                }

                Spacer()

                // ----------------------------------------------------
                // AE / AF LOCK
                // ----------------------------------------------------

                Button {

                    withAnimation(
                        .easeOut(duration: 0.15)
                    ) {

                        camera.isExposureLocked.toggle()
                    }

                } label: {

                    Image(
                        systemName:
                            camera.isExposureLocked
                            ? "lock.fill"
                            : "lock.open.fill"
                    )
                    .font(
                        .system(
                            size: 22,
                            weight: .medium
                        )
                    )
                    .foregroundColor(
                        camera.isExposureLocked
                        ? .yellow
                        : .white
                    )
                    .frame(
                        width: 54,
                        height: 54
                    )
                    .background(
                        Color.white.opacity(0.12)
                    )
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                Color.white.opacity(0.20),
                                lineWidth: 1
                            )
                    )
                }
                .onChange(
                    of: camera.isExposureLocked
                ) { _, locked in

                    camera.toggleExposureLock(
                        lock: locked
                    )
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 6)
        }
        .padding(.top, 10)
    }

    // ============================================================
    // MARK: - BLACKOUT
    // ============================================================

    private func enterBlackout() {

        previousBrightness =
            UIScreen.main.brightness

        UIScreen.main.brightness = 0.0

        withAnimation(
            .easeInOut(duration: 0.2)
        ) {

            isBlackoutMode = true
        }
    }

    private func wakeFromBlackout() {

        UIScreen.main.brightness =
            previousBrightness

        withAnimation(
            .easeInOut(duration: 0.2)
        ) {

            isBlackoutMode = false
        }
    }
}

// ============================================================
// MARK: - CAMERA TRACKER
// ============================================================

final class CameraTracker:
    NSObject,
    ObservableObject,
    AVCaptureVideoDataOutputSampleBufferDelegate {

    // ============================================================
    // PUBLISHED UI STATE
    // ============================================================

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

    // ============================================================
    // CAMERA
    // ============================================================

    private let captureSession =
        AVCaptureSession()

    private let videoQueue =
        DispatchQueue(
            label: "com.facetrackcam.videoQueue",
            qos: .userInitiated
        )

    private let context =
        CIContext()

    // ============================================================
    // FACE TRACKING
    // ============================================================

    private var currentFaceRect =
        CGRect(
            x: 0.25,
            y: 0.25,
            width: 0.50,
            height: 0.50
        )

    // ============================================================
    // BACKGROUND
    // ============================================================

    private let segmentationRequest =
        VNGeneratePersonSegmentationRequest()

    private var customBackgroundImage: CIImage?

    var hasCustomBackground: Bool {
        customBackgroundImage != nil
    }

    // ============================================================
    // SERVER
    // ============================================================

    private var listener: NWListener?

    private var connections:
        [NWConnection] = []

    // ============================================================
    // HARDWARE
    // ============================================================

    private var timer: Timer?

    // ============================================================
    // INIT
    // ============================================================

    override init() {

        super.init()

        segmentationRequest.qualityLevel =
            .balanced

        segmentationRequest.outputPixelFormat =
            kCVPixelFormatType_OneComponent8

        loadCameras()

        startMJPEGServer()

        startHardwareMonitor()
    }

    deinit {

        timer?.invalidate()

        listener?.cancel()

        captureSession.stopRunning()

        connections.forEach {
            $0.cancel()
        }
    }

    // ============================================================
    // MARK: - BATTERY
    // ============================================================

    func updateBattery() {

        DispatchQueue.main.async {

            self.batteryLevel =
                UIDevice.current.batteryLevel
        }
    }

    // ============================================================
    // MARK: - CUSTOM BACKGROUND
    // ============================================================

    func setCustomBackground(
        uiImage: UIImage
    ) {

        guard
            let ciImage =
                CIImage(
                    image: uiImage,
                    options: [
                        .applyOrientationProperty: true
                    ]
                )
        else {
            return
        }

        videoQueue.async { [weak self] in

            self?.customBackgroundImage =
                ciImage
        }
    }

    // ============================================================
    // MARK: - SCALE IMAGE TO FILL
    // ============================================================

    private func scaledToFill(
        image: CIImage,
        targetSize: CGSize
    ) -> CIImage {

        let extent = image.extent

        guard
            extent.width > 0,
            extent.height > 0,
            targetSize.width > 0,
            targetSize.height > 0
        else {
            return image
        }

        let scale = max(
            targetSize.width / extent.width,
            targetSize.height / extent.height
        )

        let scaled = image.transformed(
            by: CGAffineTransform(
                scaleX: scale,
                y: scale
            )
        )

        let scaledExtent = scaled.extent

        let cropX =
            scaledExtent.origin.x +
            (scaledExtent.width - targetSize.width) / 2

        let cropY =
            scaledExtent.origin.y +
            (scaledExtent.height - targetSize.height) / 2

        let cropRect =
            CGRect(
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

    // ============================================================
    // MARK: - HARDWARE MONITOR
    // ============================================================

    private func startHardwareMonitor() {

        DispatchQueue.main.async {

            self.batteryLevel =
                UIDevice.current.batteryLevel

            self.updateThermalState()

            self.timer =
                Timer.scheduledTimer(
                    withTimeInterval: 5.0,
                    repeats: true
                ) { [weak self] _ in

                    guard let self else {
                        return
                    }

                    self.batteryLevel =
                        UIDevice.current.batteryLevel

                    self.updateThermalState()
                }
        }
    }

    private func updateThermalState() {

        let state =
            ProcessInfo.processInfo.thermalState

        switch state {

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

    // ============================================================
    // MARK: - EXPOSURE / FOCUS LOCK
    // ============================================================

    func toggleExposureLock(
        lock: Bool
    ) {

        guard
            let input =
                captureSession.inputs
                    .compactMap({
                        $0 as? AVCaptureDeviceInput
                    })
                    .first
        else {
            return
        }

        let device = input.device

        do {

            try device.lockForConfiguration()

            if lock {

                if device.isExposureModeSupported(
                    .locked
                ) {

                    device.exposureMode =
                        .locked
                }

                if device.isWhiteBalanceModeSupported(
                    .locked
                ) {

                    device.whiteBalanceMode =
                        .locked
                }

                if device.isFocusModeSupported(
                    .locked
                ) {

                    device.focusMode =
                        .locked
                }

            } else {

                if device.isExposureModeSupported(
                    .continuousAutoExposure
                ) {

                    device.exposureMode =
                        .continuousAutoExposure
                }

                if device.isWhiteBalanceModeSupported(
                    .continuousAutoWhiteBalance
                ) {

                    device.whiteBalanceMode =
                        .continuousAutoWhiteBalance
                }

                if device.isFocusModeSupported(
                    .continuousAutoFocus
                ) {

                    device.focusMode =
                        .continuousAutoFocus
                }
            }

            device.unlockForConfiguration()

        } catch {

            print(
                "Camera configuration error: \(error)"
            )
        }
    }

    // ============================================================
    // MARK: - LOAD CAMERAS
    // ============================================================

    private func loadCameras() {

        let types:
            [AVCaptureDevice.DeviceType] = [

                .builtInWideAngleCamera,

                .builtInUltraWideCamera,

                .builtInTelephotoCamera,

                .builtInTrueDepthCamera
            ]

        let discovery =
            AVCaptureDevice.DiscoverySession(
                deviceTypes: types,
                mediaType: .video,
                position: .unspecified
            )

        let devices =
            discovery.devices

        DispatchQueue.main.async {

            self.availableCameras =
                devices

            if let front =
                devices.first(
                    where: {
                        $0.position == .front
                    }
                ) {

                self.selectedCameraID =
                    front.uniqueID

                self.switchCamera(
                    cameraID: front.uniqueID
                )

            } else if let first =
                        devices.first {

                self.selectedCameraID =
                    first.uniqueID

                self.switchCamera(
                    cameraID: first.uniqueID
                )
            }
        }
    }

    // ============================================================
    // MARK: - SWITCH CAMERA
    // ============================================================

    func switchCamera(
        cameraID: String
    ) {

        guard
            let device =
                availableCameras.first(
                    where: {
                        $0.uniqueID == cameraID
                    }
                )
        else {
            return
        }

        videoQueue.async {

            self.captureSession.beginConfiguration()

            self.captureSession.sessionPreset =
                .hd1920x1080

            // --------------------------------------------------------
            // Remove old input
            // --------------------------------------------------------

            for input in
                self.captureSession.inputs {

                self.captureSession.removeInput(
                    input
                )
            }

            // --------------------------------------------------------
            // Add new input
            // --------------------------------------------------------

            do {

                let input =
                    try AVCaptureDeviceInput(
                        device: device
                    )

                if self.captureSession.canAddInput(
                    input
                ) {

                    self.captureSession.addInput(
                        input
                    )
                }

            } catch {

                print(
                    "Unable to create camera input: \(error)"
                )
            }

            // --------------------------------------------------------
            // Video output
            // --------------------------------------------------------

            let output: AVCaptureVideoDataOutput

            if let existing =
                self.captureSession.outputs
                    .compactMap({
                        $0 as? AVCaptureVideoDataOutput
                    })
                    .first {

                output = existing

            } else {

                output =
                    AVCaptureVideoDataOutput()

                output.alwaysDiscardsLateVideoFrames =
                    true

                output.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String:
                        kCVPixelFormatType_32BGRA
                ]

                output.setSampleBufferDelegate(
                    self,
                    queue: self.videoQueue
                )

                if self.captureSession.canAddOutput(
                    output
                ) {

                    self.captureSession.addOutput(
                        output
                    )
                }
            }

            // --------------------------------------------------------
            // ORIENTATION
            // --------------------------------------------------------

            if let connection =
                output.connection(
                    with: .video
                ) {

                if connection.isVideoOrientationSupported {

                    connection.videoOrientation =
                        .portrait
                }

                if device.position == .front {

                    if connection.isVideoMirroringSupported {

                        connection.isVideoMirrored =
                            true
                    }
                } else {

                    if connection.isVideoMirroringSupported {

                        connection.isVideoMirrored =
                            false
                    }
                }
            }

            self.captureSession.commitConfiguration()

            // --------------------------------------------------------
            // Start session
            // --------------------------------------------------------

            if !self.captureSession.isRunning {

                self.captureSession.startRunning()
            }
        }
    }

    // ============================================================
    // MARK: - MJPEG SERVER
    // ============================================================

    private func startMJPEGServer() {

        do {

            listener =
                try NWListener(
                    using: .tcp,
                    on: 8080
                )

        } catch {

            print(
                "Unable to start server: \(error)"
            )

            return
        }

        listener?.stateUpdateHandler = { state in

            print(
                "MJPEG server state: \(state)"
            )
        }

        listener?.newConnectionHandler = {
            [weak self] connection in

            guard let self else {
                return
            }

            connection.start(
                queue: .global(
                    qos: .userInitiated
                )
            )

            let header =
                """
                HTTP/1.1 200 OK\r
                Content-Type: multipart/x-mixed-replace; boundary=frame\r
                Cache-Control: no-cache\r
                Connection: close\r
                Pragma: no-cache\r
                \r
                """

            connection.send(
                content: header.data(
                    using: .utf8
                ),
                completion:
                    .contentProcessed {
                        _ in
                    }
            )

            self.videoQueue.async {

                self.connections.append(
                    connection
                )
            }
        }

        listener?.start(
            queue: .global(
                qos: .userInitiated
            )
        )
    }

    // ============================================================
    // MARK: - CAMERA FRAME PROCESSING
    // ============================================================

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {

        guard
            let pixelBuffer =
                CMSampleBufferGetImageBuffer(
                    sampleBuffer
                )
        else {
            return
        }

        // ========================================================
        // CREATE IMAGE
        // ========================================================

        var currentCIImage =
            CIImage(
                cvPixelBuffer: pixelBuffer
            )

        let originalExtent =
            currentCIImage.extent

        // ========================================================
        // BACKGROUND REPLACEMENT
        // ========================================================

        if backgroundMode != .off {

            let segmentationHandler =
                VNImageRequestHandler(
                    cvPixelBuffer: pixelBuffer,
                    options: [:]
                )

            do {

                try segmentationHandler.perform(
                    [segmentationRequest]
                )

            } catch {

                print(
                    "Segmentation error: \(error)"
                )
            }

            if let maskObservation =
                segmentationRequest.results?.first {

                let maskImage =
                    CIImage(
                        cvPixelBuffer:
                            maskObservation.pixelBuffer
                    )

                let scaleX =
                    originalExtent.width /
                    maskImage.extent.width

                let scaleY =
                    originalExtent.height /
                    maskImage.extent.height

                let scaledMask =
                    maskImage.transformed(
                        by: CGAffineTransform(
                            scaleX: scaleX,
                            y: scaleY
                        )
                    )

                var backgroundImage:
                    CIImage?

                switch backgroundMode {

                case .off:

                    backgroundImage = nil

                case .portrait:

                    let blurFilter =
                        CIFilter.gaussianBlur()

                    blurFilter.inputImage =
                        currentCIImage

                    blurFilter.radius =
                        15.0

                    backgroundImage =
                        blurFilter.outputImage?
                            .cropped(
                                to: originalExtent
                            )

                case .custom:

                    if let customBG =
                        customBackgroundImage {

                        backgroundImage =
                            scaledToFill(
                                image: customBG,
                                targetSize:
                                    originalExtent.size
                            )
                    }
                }

                if let bg =
                    backgroundImage {

                    let blendFilter =
                        CIFilter.blendWithMask()

                    blendFilter.inputImage =
                        currentCIImage

                    blendFilter.backgroundImage =
                        bg

                    blendFilter.maskImage =
                        scaledMask

                    if let result =
                        blendFilter.outputImage {

                        currentCIImage =
                            result
                    }
                }
            }
        }

        // ========================================================
        // FACE TRACKING / AUTO CROP
        // ========================================================

        var finalCIImage =
            currentCIImage

        if isFaceTrackingEnabled {

            let request =
                VNDetectFaceRectanglesRequest()

            let handler =
                VNImageRequestHandler(
                    ciImage: currentCIImage,
                    options: [:]
                )

            do {

                try handler.perform(
                    [request]
                )

            } catch {

                print(
                    "Face detection error: \(error)"
                )
            }

            if let face =
                request.results?.first {

                let target =
                    face.boundingBox

                // Smooth movement
                currentFaceRect.origin.x +=
                    (target.origin.x -
                     currentFaceRect.origin.x) *
                    0.12

                currentFaceRect.origin.y +=
                    (target.origin.y -
                     currentFaceRect.origin.y) *
                    0.12

                currentFaceRect.size.width +=
                    (target.width -
                     currentFaceRect.size.width) *
                    0.12

                currentFaceRect.size.height +=
                    (target.height -
                     currentFaceRect.size.height) *
                    0.12

                let width =
                    originalExtent.width

                let height =
                    originalExtent.height

                // ------------------------------------------------
                // Face center
                // ------------------------------------------------

                let centerX =
                    (
                        currentFaceRect.origin.x +
                        currentFaceRect.width / 2
                    ) * width

                let centerY =
                    (
                        1.0 -
                        currentFaceRect.origin.y -
                        currentFaceRect.height / 2
                    ) * height

                // ------------------------------------------------
                // Preserve camera aspect ratio
                // ------------------------------------------------

                let aspect =
                    width / height

                let faceWidth =
                    currentFaceRect.width *
                    width

                let desiredWidth =
                    faceWidth *
                    max(
                        1.0,
                        zoomIntensity
                    )

                let cropWidth =
                    min(
                        desiredWidth,
                        width
                    )

                let cropHeight =
                    min(
                        cropWidth / aspect,
                        height
                    )

                // ------------------------------------------------
                // Center crop around face
                // ------------------------------------------------

                var cropX =
                    centerX -
                    cropWidth / 2

                var cropY =
                    centerY -
                    cropHeight / 2

                cropX =
                    max(
                        0,
                        min(
                            cropX,
                            width -
                            cropWidth
                        )
                    )

                cropY =
                    max(
                        0,
                        min(
                            cropY,
                            height -
                            cropHeight
                        )
                    )

                let cropRect =
                    CGRect(
                        x: cropX,
                        y: cropY,
                        width: cropWidth,
                        height: cropHeight
                    )

                finalCIImage =
                    currentCIImage.cropped(
                        to: cropRect
                    )
            }
        }

        // ========================================================
        // CREATE CGIMAGE
        // ========================================================

        guard
            let outputCG =
                context.createCGImage(
                    finalCIImage,
                    from: finalCIImage.extent
                )
        else {
            return
        }

        // ========================================================
        // UPDATE SWIFTUI
        // ========================================================

        DispatchQueue.main.async {

            self.currentFrame =
                outputCG
        }

        // ========================================================
        // SEND MJPEG
        // ========================================================

        let uiImage =
            UIImage(
                cgImage: outputCG
            )

        guard
            let jpeg =
                uiImage.jpegData(
                    compressionQuality: 0.60
                )
        else {
            return
        }

        let header =
            """
            --frame\r
            Content-Type: image/jpeg\r
            Content-Length: \(jpeg.count)\r
            \r
            """

        guard
            let headerData =
                header.data(using: .utf8),
            let endingData =
                "\r\n".data(using: .utf8)
        else {
            return
        }

        let packet =
            headerData +
            jpeg +
            endingData

        // --------------------------------------------------------
        // Remove dead connections
        // --------------------------------------------------------

        connections.removeAll { connection in
            switch connection.state {
            case .cancelled, .failed:
                return true
            default:
                return false
            }
        }

        // --------------------------------------------------------
        // Send frame
        // --------------------------------------------------------

        for connection in connections {

            connection.send(
                content: packet,
                completion:
                    .contentProcessed {
                        _ in
                    }
            )
        }
    }

    // ============================================================
    // MARK: - WIFI ADDRESS
    // ============================================================

    func getWiFiAddress() -> String {
        var address = "Not Connected"

        var interfaceAddress: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&interfaceAddress) == 0 else {
            return address
        }

        var pointer = interfaceAddress

        while pointer != nil {

            guard let interface = pointer?.pointee else {
                break
            }

            defer {
                pointer = interface.ifa_next
            }

            guard let addr = interface.ifa_addr else {
                continue
            }

            if addr.pointee.sa_family == UInt8(AF_INET) {

                let interfaceName = String(
                    cString: interface.ifa_name
                )

                if interfaceName == "en0" {

                    var hostname = [CChar](
                        repeating: 0,
                        count: Int(NI_MAXHOST)
                    )

                    let result = getnameinfo(
                        addr,
                        socklen_t(addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )

                    if result == 0 {

                        let ipAddress = String(
                            cString: hostname
                        )

                        address = "http://\(ipAddress):8080"
                    }
                }
            }
        }

        freeifaddrs(interfaceAddress)

        return address
    }
}
