import SwiftUI
import PhotosUI
import UIKit

private enum ToolPanel: String, Identifiable, CaseIterable, Equatable {
    case faceTrack = "FaceTrack", background = "Background", exposure = "AE", whiteBalance = "WB", settings = "Settings"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .faceTrack: return "viewfinder"
        case .background: return "person.crop.rectangle"
        case .exposure: return "sun.max"
        case .whiteBalance: return "thermometer.sun"
        case .settings: return "gearshape"
        }
    }
    static var allCases: [ToolPanel] { [.faceTrack, .background, .exposure, .whiteBalance, .settings] }
}

private extension View {
    func liquidGlass(cornerRadius: CGFloat = 26) -> some View {
        background(LiquidGlassBackground().clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.1), .white.opacity(0.015)], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(.white.opacity(0.22), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.24), radius: 16, y: 8)
    }

    func glassCapsule() -> some View {
        background(LiquidGlassBackground().clipShape(Capsule()))
            .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 0.7))
    }
}

private struct MagneticSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let defaultValue: Float
    let step: Float

    var body: some View {
        Slider(value: snappedBinding, in: range, step: step)
            .tint(.white)
            .padding(.horizontal, 10)
            .frame(height: 42)
            .background(LiquidGlassBackground().clipShape(Capsule()))
            .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.7))
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

}

struct CameraScreen: View {
    @StateObject private var camera = CameraModel()
    @Environment(\.scenePhase) private var phase
    @State private var panel: ToolPanel?
    @State private var showConnection = false
    @State private var showRecentBackground = false
    @State private var photo: PhotosPickerItem?
    @State private var loadingPhoto = false
    @State private var iconAngle: Angle = .zero

    var body: some View {
        ZStack {
            preview
            VStack(spacing: 0) { topBar; Spacer(minLength: 0); controls }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .statusBarHidden()
        .fontDesign(.default)
        .tint(Color("mijick-background-yellow"))
        .onAppear { camera.activate(); updateIconAngle() }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in updateIconAngle() }
        .onChange(of: phase) { _, value in
            if value == .active { camera.activate() } else if value == .background { camera.deactivate() }
        }
        .overlay(alignment: .bottom) {
            if let panel {
                compactPanel(for: panel)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 148)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: panel)
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
            HStack(spacing: 8) {
                ForEach(ToolPanel.allCases) { tool in
                    Button {
                        FaceTrackHaptics.tap()
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) { panel = panel == tool ? nil : tool }
                    } label: {
                        Image(systemName: tool.icon).font(.system(size: 17, weight: .semibold)).rotationEffect(iconAngle)
                            .frame(width: 54, height: 46)
                    }
                    .foregroundStyle(tool == .faceTrack && camera.settings.tracking ? Color("mijick-background-yellow") : .white)
                    .glassCapsule()
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
                MijickRoundButton(icon: "mijick-icon-change-camera", label: "Switch camera", rotation: iconAngle) { camera.flipCamera() }
                    .disabled(!camera.ready)
            }
            .padding(.horizontal, 24)
        }
        .padding(.horizontal, 16).padding(.bottom, 26)
    }

    @ViewBuilder
    private func compactPanel(for panel: ToolPanel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(panel.rawValue).font(.headline.weight(.semibold))
                Spacer()
                Button { FaceTrackHaptics.tap(); withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) { self.panel = nil } } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).frame(width: 32, height: 32)
                }
                .foregroundStyle(.white).background(.white.opacity(0.12), in: Circle())
            }
            switch panel {
            case .settings:
                settingsPanel
            default:
                ScrollView(.vertical, showsIndicators: false) { panelContent(panel) }
            }
        }
        .padding(12).frame(maxWidth: .infinity).frame(maxHeight: panel == .settings ? 204 : 224)
        .liquidGlass(cornerRadius: 28)
    }

    @ViewBuilder
    private func panelContent(_ panel: ToolPanel) -> some View {
        switch panel {
        case .faceTrack: trackingPanel
        case .background: backgroundPanel
        case .exposure: exposurePanel
        case .whiteBalance: whiteBalancePanel
        case .settings: settingsPanel
        }
    }

    private var trackingPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Face follow", systemImage: "viewfinder")
                Spacer()
            }
            HStack(spacing: 10) {
                Toggle("On", isOn: $camera.settings.tracking)
                    .labelsHidden()
                    .tint(Color("mijick-background-yellow"))
                    .onChange(of: camera.settings.tracking) { _, _ in FaceTrackHaptics.tap() }
                Slider(value: $camera.settings.intensity, in: 0.8...2.2, step: 0.1) { editing in if editing { FaceTrackHaptics.tap() } }
                    .tint(Color("mijick-background-yellow"))
                    .padding(.horizontal, 10).frame(height: 42)
                    .background(LiquidGlassBackground().clipShape(Capsule()))
                    .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.7))
                    .onChange(of: camera.settings.intensity) { _, _ in FaceTrackHaptics.selection() }
                Text(String(format: "%.1f×", camera.settings.intensity)).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Text("Keeps face, shoulders, chest, and headwear in frame.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var backgroundPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                backgroundChoice(.off, "Off", "circle.slash")
                backgroundChoice(.blur, "Portrait", "person.crop.rectangle")
                backgroundChoice(.custom, "Custom", "photo")
            }
            if camera.settings.background == .custom {
                Button { FaceTrackHaptics.tap(); withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) { showRecentBackground.toggle() } } label: {
                    HStack { Label("Recent", systemImage: "clock.arrow.circlepath"); Spacer(); Image(systemName: showRecentBackground ? "chevron.up" : "chevron.down") }
                        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                }
                .foregroundStyle(.white).glassCapsule()
                if showRecentBackground {
                    VStack(alignment: .leading, spacing: 8) {
                        if camera.hasBackground {
                            Button { FaceTrackHaptics.tap(); camera.settings.background = .custom } label: { Label("Use recent photo", systemImage: "checkmark.circle") }
                            Button(role: .destructive) { FaceTrackHaptics.tap(); camera.clearBackground(); showRecentBackground = true } label: { Label("Clear recent", systemImage: "trash") }
                        } else { Text("No recent background yet.").font(.caption).foregroundStyle(.secondary) }
                        PhotosPicker(selection: $photo, matching: .images) {
                            Label(loadingPhoto ? "Loading…" : "Choose from Photos", systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .disabled(loadingPhoto).glassCapsule()
                    }
                    .padding(10).liquidGlass(cornerRadius: 18)
                }
            }
        }
    }

    private func backgroundChoice(_ mode: BackgroundMode, _ title: String, _ icon: String) -> some View {
        Button {
            FaceTrackHaptics.tap()
            camera.settings.background = mode
            if mode == .custom { showRecentBackground = true }
        } label: {
            Label(title, systemImage: icon).font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 42)
        }
        .foregroundStyle(camera.settings.background == mode ? Color("mijick-background-yellow") : .white)
        .glassCapsule()
    }

    private var exposurePanel: some View {
        exposureLikePanel(title: "Auto exposure", icon: "sun.max", locked: $camera.exposureLocked) {
            Text(String(format: "%+.1f", camera.exposure)).font(.caption.monospaced()).foregroundStyle(.secondary)
            MagneticSlider(value: $camera.exposure, range: -2...2, defaultValue: 0, step: 0.1)
        }
    }

    private var whiteBalancePanel: some View {
        exposureLikePanel(title: "White balance", icon: "thermometer.sun", locked: $camera.whiteBalanceLocked) {
            Text("\(Int(camera.whiteBalanceTemperature))K").font(.caption.monospaced()).foregroundStyle(.secondary)
            MagneticSlider(value: $camera.whiteBalanceTemperature, range: 2500...7500, defaultValue: 4500, step: 100)
        }
    }

    private func exposureLikePanel<SliderContent: View>(title: String, icon: String, locked: Binding<Bool>, @ViewBuilder slider: () -> SliderContent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle("On", isOn: locked)
                    .labelsHidden()
                    .tint(Color("mijick-background-yellow"))
                    .onChange(of: locked.wrappedValue) { _, _ in FaceTrackHaptics.tap() }
                HStack(spacing: 8) { Image(systemName: icon); slider() }
            }
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var settingsPanel: some View {
        List {
            Section("Camera") {
                Menu {
                    ForEach(camera.cameras) { choice in Button(choice.name) { FaceTrackHaptics.tap(); camera.switchCamera(choice.id) } }
                } label: { settingRow("Lens", camera.cameras.first(where: { $0.id == camera.selectedCamera })?.name ?? "Front", "camera") }
                Menu {
                    ForEach(VideoQuality.allCases) { quality in Button(quality.rawValue) { FaceTrackHaptics.tap(); camera.settings.quality = quality } }
                } label: { settingRow("Quality", camera.settings.quality.rawValue, "sparkles.tv") }
            }
            Section("Preview") {
                Toggle("Mirror selfie", isOn: $camera.mirrorPreview).onChange(of: camera.mirrorPreview) { _, _ in FaceTrackHaptics.tap() }
                Toggle("Mirror stream", isOn: $camera.settings.mirrorStream).onChange(of: camera.settings.mirrorStream) { _, _ in FaceTrackHaptics.tap() }
            }
            Section("Connect") {
                Button { FaceTrackHaptics.tap(); withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) { showConnection.toggle() } } label: {
                    HStack { Label("Connect", systemImage: "network"); Spacer(); Image(systemName: showConnection ? "chevron.up" : "chevron.down") }
                }
                if showConnection { connectionDetails }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .frame(maxHeight: 224)
        .fontDesign(.default)
    }

    private func settingRow(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            VStack(alignment: .leading, spacing: 1) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.subheadline.weight(.medium)) }
            Spacer()
            Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var connectionDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Viewers", value: "\(camera.viewers)")
            if let url = camera.wifiURL { compactURLRow("Wi‑Fi", url) }
            compactURLRow("USB", camera.usbURL)
        }
        .padding(8).liquidGlass(cornerRadius: 18)
    }

    private func compactURLRow(_ title: String, _ url: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) { Text(title).font(.caption).foregroundStyle(.secondary); Text(url).font(.caption2.monospaced()).lineLimit(2).textSelection(.enabled) }
            Spacer()
            Button { FaceTrackHaptics.tap(); UIPasteboard.general.string = url } label: { Image(systemName: "doc.on.doc").frame(width: 34, height: 34) }.disabled(!camera.streaming)
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

