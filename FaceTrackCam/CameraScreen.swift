import SwiftUI
import PhotosUI
import UIKit

private enum ToolPanel: String, Identifiable, CaseIterable {
    case tracking = "Tracking", background = "Background", camera = "Camera"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .tracking: return "viewfinder"
        case .background: return "person.crop.rectangle"
        case .camera: return "slider.horizontal.3"
        }
    }
    static var allCases: [ToolPanel] { [.tracking, .background, .camera] }
}

private enum CameraControl: Equatable { case exposure, whiteBalance }

private extension View {
    func liquidGlass(cornerRadius: CGFloat = 26) -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(.white.opacity(0.2), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.24), radius: 16, y: 8)
    }
}

private struct MagneticSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let defaultValue: Float
    let step: Float

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Capsule().fill(.white.opacity(0.12)).frame(height: 4)
                Circle().fill(.white.opacity(0.22)).frame(width: 20, height: 20).blur(radius: 5)
                    .position(x: markerX(in: proxy.size.width), y: proxy.size.height / 2)
                Slider(value: snappedBinding, in: range, step: step).tint(.white)
            }
        }
        .frame(height: 30)
    }

    private var snappedBinding: Binding<Float> {
        Binding(get: { value }, set: { newValue in
            let snapDistance = max(step * 1.5, (range.upperBound - range.lowerBound) * 0.018)
            let next = abs(newValue - defaultValue) <= snapDistance ? defaultValue : newValue
            if next == defaultValue && value != defaultValue { FaceTrackHaptics.snap() }
            else if next != value { FaceTrackHaptics.selection() }
            value = next
        })
    }

    private func markerX(in width: CGFloat) -> CGFloat {
        let fraction = CGFloat((defaultValue - range.lowerBound) / (range.upperBound - range.lowerBound))
        return max(10, min(width - 10, width * fraction))
    }
}

struct CameraScreen: View {
    @StateObject private var camera = CameraModel()
    @Environment(\.scenePhase) private var phase
    @State private var panel: ToolPanel?
    @State private var cameraControl: CameraControl?
    @State private var showConnection = false
    @State private var photo: PhotosPickerItem?
    @State private var loadingPhoto = false
    @State private var iconAngle: Angle = .zero

    var body: some View {
        ZStack {
            preview
            VStack(spacing: 0) { topBar; Spacer(minLength: 0); controls }
        }
        .background(Color.black).ignoresSafeArea().statusBarHidden()
        .tint(Color("mijick-background-yellow"))
        .onAppear { camera.activate(); updateIconAngle() }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in updateIconAngle() }
        .onChange(of: phase) { _, value in
            if value == .active { camera.activate() } else if value == .background { camera.deactivate() }
        }
        .overlay(alignment: .bottom) {
            if let panel {
                compactPanel(for: panel).padding(.horizontal, 14).padding(.bottom, 148)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: panel)
        .alert("FaceTrackCam", isPresented: Binding(get: { camera.error != nil }, set: { if !$0 { camera.error = nil } })) {
            if camera.permissionDenied { Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } }
            Button("OK", role: .cancel) { camera.error = nil }
        } message: { Text(camera.error ?? "") }
        .task(id: photo) {
            guard let selected = photo else { return }
            loadingPhoto = true; defer { if !Task.isCancelled { loadingPhoto = false } }
            do {
                if let data = try await selected.loadTransferable(type: Data.self), !Task.isCancelled { camera.loadBackground(data) }
            } catch { if !Task.isCancelled { camera.error = "Photo could not be loaded." } }
        }
        .overlay { if camera.dimmed { dimOverlay } }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Image(systemName: camera.battery.map { $0 <= 20 ? "battery.25" : "battery.100" } ?? "battery.100")
                .font(.system(size: 19, weight: .medium)).rotationEffect(iconAngle).accessibilityLabel("Battery")
            Spacer(minLength: 0)
            Button { FaceTrackHaptics.tap(); camera.oledSaverEnabled.toggle() } label: {
                Image(systemName: camera.oledSaverEnabled ? "moon.fill" : "moon").frame(width: 44, height: 44).rotationEffect(iconAngle)
            }
            .foregroundStyle(camera.oledSaverEnabled ? Color("mijick-background-yellow") : .white)
            .accessibilityLabel(camera.oledSaverEnabled ? "Turn OLED saver off" : "Turn OLED saver on")
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 10)
    }

    private var preview: some View {
        ZStack {
            Color.black
            if camera.ready { ProcessedPreview(frames: camera.preview, mirrored: camera.frontCamera && camera.mirrorPreview != camera.settings.mirrorStream) }
            else { Image(systemName: camera.permissionDenied ? "camera.fill" : "camera").font(.largeTitle).foregroundStyle(.secondary) }
        }
        .clipped().frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                ForEach(ToolPanel.allCases) { tool in
                    Button {
                        FaceTrackHaptics.tap()
                        withAnimation { panel = panel == tool ? nil : tool }
                    } label: {
                        Image(systemName: tool.icon).font(.system(size: 18, weight: .semibold)).rotationEffect(iconAngle).frame(width: 54, height: 46)
                    }
                    .foregroundStyle(tool == .tracking && camera.settings.tracking ? Color("mijick-background-yellow") : .white)
                    .background(.ultraThinMaterial, in: Capsule()).overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.7))
                    .accessibilityLabel(tool.rawValue)
                }
            }
            HStack {
                MijickRoundButton(icon: "mijick-icon-light", active: camera.torch, label: "Toggle torch", rotation: iconAngle) { camera.toggleTorch() }
                    .disabled(!camera.ready || !camera.hasTorch).opacity(camera.hasTorch ? 1 : 0.3)
                Spacer()
                StreamButton(active: camera.streaming, starting: camera.starting) { camera.toggleStream() }
                    .disabled(!camera.ready && !camera.streaming && !camera.starting)
                Spacer()
                MijickRoundButton(icon: "mijick-icon-change-camera", label: "Switch camera", rotation: iconAngle) { camera.flipCamera() }.disabled(!camera.ready)
            }
        }
        .padding(.top, 10).padding(.bottom, 26).padding(.horizontal, 24)
    }

    @ViewBuilder
    private func compactPanel(for panel: ToolPanel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(panel.rawValue).font(.headline.weight(.semibold))
                Spacer()
                Button { FaceTrackHaptics.tap(); withAnimation { self.panel = nil } } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).frame(width: 32, height: 32)
                }
                .foregroundStyle(.white).background(.white.opacity(0.12), in: Circle())
            }
            ScrollView(.vertical, showsIndicators: false) {
                switch panel {
                case .tracking: trackingPanel
                case .background: backgroundPanel
                case .camera: cameraPanel
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity).frame(maxHeight: 300).liquidGlass(cornerRadius: 28)
    }

    private var trackingPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Face follow", systemImage: "viewfinder")
                Spacer()
                Button { FaceTrackHaptics.tap(); camera.settings.tracking.toggle() } label: {
                    Image(systemName: camera.settings.tracking ? "checkmark" : "pause.fill").frame(width: 40, height: 36)
                }
                .foregroundStyle(camera.settings.tracking ? Color("mijick-background-yellow") : .white).background(.white.opacity(0.1), in: Capsule())
            }
            HStack(spacing: 10) {
                Text("Frame").font(.subheadline)
                Slider(value: $camera.settings.intensity, in: 0.8...2.2, step: 0.1) { editing in if editing { FaceTrackHaptics.tap() } }
                    .tint(Color("mijick-background-yellow")).onChange(of: camera.settings.intensity) { _, _ in FaceTrackHaptics.selection() }
                Text(String(format: "%.1f×", camera.settings.intensity)).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Text("Keeps face, shoulders, chest, and headwear in frame.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var backgroundPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                backgroundChoice(.off, "Off", "circle.slash")
                backgroundChoice(.blur, "Blur", "aqi.medium")
                backgroundChoice(.custom, "Photo", "photo")
            }
            if camera.settings.background == .custom || camera.hasBackground {
                HStack(spacing: 10) {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label(loadingPhoto ? "Loading…" : (camera.hasBackground ? "Recent photo" : "Pick photo"), systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .disabled(loadingPhoto).background(.white.opacity(0.1), in: Capsule())
                    if camera.hasBackground {
                        Button { FaceTrackHaptics.tap(); camera.settings.background = .custom } label: { Image(systemName: "checkmark").frame(width: 40, height: 40) }
                            .background(.white.opacity(0.1), in: Circle())
                    }
                }
            }
        }
    }

    private func backgroundChoice(_ mode: BackgroundMode, _ title: String, _ icon: String) -> some View {
        Button { FaceTrackHaptics.tap(); camera.settings.background = mode } label: {
            Label(title, systemImage: icon).font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 42)
        }
        .foregroundStyle(camera.settings.background == mode ? Color("mijick-background-yellow") : .white)
        .background(.white.opacity(camera.settings.background == mode ? 0.18 : 0.08), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 0.6))
    }

    private var cameraPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(camera.cameras) { choice in Button(choice.name) { FaceTrackHaptics.tap(); camera.switchCamera(choice.id) } }
                } label: { settingBlob("Lens", camera.cameras.first(where: { $0.id == camera.selectedCamera })?.name ?? "Front", "camera") }
                Menu {
                    ForEach(VideoQuality.allCases) { quality in Button(quality.rawValue) { FaceTrackHaptics.tap(); camera.settings.quality = quality } }
                } label: { settingBlob("Quality", camera.settings.quality.rawValue, "sparkles.tv") }
            }
            HStack(spacing: 8) {
                settingBlob("Exposure", camera.exposureLocked ? "Locked" : "Auto", "sun.max")
                    .onTapGesture { FaceTrackHaptics.tap(); withAnimation { cameraControl = cameraControl == .exposure ? nil : .exposure } }
                settingBlob("White balance", camera.whiteBalanceLocked ? "Locked" : "Auto", "thermometer.sun")
                    .onTapGesture { FaceTrackHaptics.tap(); withAnimation { cameraControl = cameraControl == .whiteBalance ? nil : .whiteBalance } }
            }
            if cameraControl == .exposure { exposureEditor }
            if cameraControl == .whiteBalance { whiteBalanceEditor }
            HStack(spacing: 8) {
                Toggle(isOn: $camera.mirrorPreview) { Label("Selfie", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") }
                    .toggleStyle(.button).tint(camera.mirrorPreview ? Color("mijick-background-yellow") : .white)
                    .onChange(of: camera.mirrorPreview) { _, _ in FaceTrackHaptics.tap() }
                Toggle(isOn: $camera.settings.mirrorStream) { Label("Stream", systemImage: "dot.radiowaves.left.and.right") }
                    .toggleStyle(.button).tint(camera.settings.mirrorStream ? Color("mijick-background-yellow") : .white)
                    .onChange(of: camera.settings.mirrorStream) { _, _ in FaceTrackHaptics.tap() }
            }
            Button { FaceTrackHaptics.tap(); withAnimation { showConnection.toggle() } } label: {
                HStack { Label("Connect", systemImage: "network"); Spacer(); Image(systemName: showConnection ? "chevron.up" : "chevron.down") }
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            }
            .foregroundStyle(.white).background(.white.opacity(0.1), in: Capsule())
            if showConnection { connectionDetails }
        }
    }

    private func settingBlob(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.subheadline.weight(.medium)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .foregroundStyle(.white).background(.white.opacity(0.09), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 0.6))
    }

    private var exposureEditor: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Exposure bias").font(.caption).foregroundStyle(.secondary)
                Text(String(format: "%+.1f", camera.exposure)).font(.caption.monospaced())
            }
            MagneticSlider(value: $camera.exposure, range: -2...2, defaultValue: 0, step: 0.1)
            Button { FaceTrackHaptics.tap(); camera.exposureLocked.toggle() } label: {
                Image(systemName: camera.exposureLocked ? "lock.fill" : "lock.open").frame(width: 42, height: 38)
            }
            .foregroundStyle(camera.exposureLocked ? Color("mijick-background-yellow") : .white).background(.white.opacity(0.1), in: Capsule())
        }
    }

    private var whiteBalanceEditor: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("White balance").font(.caption).foregroundStyle(.secondary)
                Text("\(Int(camera.whiteBalanceTemperature))K").font(.caption.monospaced())
            }
            MagneticSlider(value: $camera.whiteBalanceTemperature, range: 2500...7500, defaultValue: 4500, step: 100)
            Button { FaceTrackHaptics.tap(); camera.whiteBalanceLocked.toggle() } label: {
                Image(systemName: camera.whiteBalanceLocked ? "lock.fill" : "lock.open").frame(width: 42, height: 38)
            }
            .foregroundStyle(camera.whiteBalanceLocked ? Color("mijick-background-yellow") : .white).background(.white.opacity(0.1), in: Capsule())
        }
    }

    private var connectionDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Viewers", value: "\(camera.viewers)")
            if let url = camera.wifiURL { compactURLRow("Wi‑Fi", url) }
            compactURLRow("USB", camera.usbURL)
        }
        .padding(12).liquidGlass(cornerRadius: 18)
    }

    private func compactURLRow(_ title: String, _ url: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(url).font(.caption2.monospaced()).lineLimit(2).textSelection(.enabled)
            }
            Spacer()
            Button { FaceTrackHaptics.tap(); UIPasteboard.general.string = url } label: { Image(systemName: "doc.on.doc").frame(width: 34, height: 34) }
                .disabled(!camera.streaming)
        }
    }

    private var dimOverlay: some View {
        Color.black.ignoresSafeArea().contentShape(Rectangle()).onTapGesture { FaceTrackHaptics.tap(); camera.dimmed = false }
            .accessibilityLabel("OLED saver active. Tap to wake.")
    }

    private func updateIconAngle() {
        switch UIDevice.current.orientation {
        case .landscapeLeft: iconAngle = .degrees(90)
        case .landscapeRight: iconAngle = .degrees(-90)
        default: iconAngle = .zero
        }
    }
}

