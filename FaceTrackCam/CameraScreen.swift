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
    @State private var lastRaw: Float?
    @State private var snapped = false

    var body: some View {
        GeometryReader { geometry in
            let travel = max(1, geometry.size.width - 40)
            let fraction = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.28)).frame(height: 4).padding(.horizontal, 20)
                Capsule().fill(.white).frame(width: max(0, travel * fraction), height: 4).offset(x: 20)
                Capsule().fill(.ultraThinMaterial)
                    .overlay(LiquidGlassBackground(style: .systemUltraThinMaterial).clipShape(Capsule()))
                    .overlay(Capsule().stroke(.white.opacity(0.7), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    .frame(width: 40, height: 24).offset(x: travel * fraction)
            }
            .frame(height: 48).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                let ratio = Float(min(1, max(0, (gesture.location.x - 20) / travel)))
                let raw = range.lowerBound + ratio * (range.upperBound - range.lowerBound)
                let crossed = lastRaw.map { ($0 - defaultValue) * (raw - defaultValue) < 0 } ?? false
                let near = abs(raw - defaultValue) < (range.upperBound - range.lowerBound) * 0.025
                let shouldSnap = near || (crossed && !snapped)
                if shouldSnap && !snapped { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
                let next = shouldSnap ? defaultValue : min(range.upperBound, max(range.lowerBound, (raw / step).rounded() * step))
                if next != value && !shouldSnap { FaceTrackHaptics.selection() }
                value = next; snapped = shouldSnap; lastRaw = raw
            }.onEnded { _ in lastRaw = nil; snapped = false })
        }
        .frame(height: 48)
        .accessibilityElement().accessibilityValue(String(format: "%.1f", value))
        .accessibilityAdjustableAction { direction in
            value = min(range.upperBound, max(range.lowerBound, value + (direction == .increment ? step : -step)))
            FaceTrackHaptics.selection()
        }
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
    @State private var showPhotoPicker = false
    @AppStorage("framingGrid") private var showGrid = false

    var body: some View {
        preview.ignoresSafeArea()
        .overlay { if showGrid { framingGrid.ignoresSafeArea().allowsHitTesting(false) } }
        .safeAreaInset(edge: .top, spacing: 0) { topBar.background(Color.clear) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if let panel {
                    panelContent(panel).padding(.horizontal, panel == .settings ? 0 : 24)
                        .opacity(camera.streaming ? 0.55 : 1)
                        .transition(.asymmetric(insertion: .scale(scale: 0.95, anchor: .bottom).combined(with: .opacity), removal: .scale(scale: 0.95, anchor: .bottom).combined(with: .opacity)))
                }
                controls
            }.background(Color.clear)
        }
        .statusBarHidden().fontDesign(.default).tint(.white)
        .environment(\.colorScheme, .dark)
        .buttonStyle(LiquidGlassButtonStyle())
        .onAppear { camera.activate(); updateIconAngle() }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in updateIconAngle() }
        .onChange(of: phase) { _, value in
            if value == .active { camera.activate() } else if value == .background { camera.deactivate() }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photo, matching: .images)

        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: panel)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: showRecentBackground)
        .animation(.easeInOut(duration: 0.25), value: camera.streaming)
        .alert("FacePull", isPresented: Binding(get: { camera.error != nil }, set: { if !$0 { camera.error = nil } })) {
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
            Button { camera.oledSaverEnabled.toggle() } label: {
                Image(systemName: camera.oledSaverEnabled ? "moon.fill" : "moon").frame(width: 44, height: 44).rotationEffect(iconAngle)
            }
            .foregroundStyle(camera.oledSaverEnabled ? Color("mijick-background-yellow") : .white)
            .accessibilityLabel(camera.oledSaverEnabled ? "Turn OLED saver off" : "Turn OLED saver on")
        }
        .padding(.horizontal, 24)
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
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(ToolPanel.allCases) { tool in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { panel = panel == tool ? nil : tool }
                    } label: {
                        Image(systemName: tool.icon).font(.system(size: 17, weight: .semibold)).rotationEffect(iconAngle)
                            .frame(width: 44, height: 44)
                            .glassCapsule()
                    }
                    .foregroundStyle(panel == tool ? Color.white : Color.white.opacity(0.8))
                    .shadow(color: .white.opacity(panel == tool ? 0.3 : 0), radius: 8)
                    .accessibilityLabel(tool.rawValue)
                    .accessibilityAddTraits(panel == tool ? .isSelected : [])
                }
            }
            .padding(.bottom, 20)
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
        .padding(.horizontal, 16).padding(.bottom, 8)
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
        sliderRow("Face tracking", enabled: $camera.settings.tracking,
            value: Binding(get: { Float(camera.settings.intensity) }, set: { camera.settings.intensity = CGFloat($0) }),
            range: 0.8...2.2, center: 1.8, step: 0.1)
    }

    private var exposurePanel: some View {
        sliderRow("Exposure lock", enabled: $camera.exposureLocked, value: $camera.exposure,
                  range: -2...2, center: 0, step: 0.1)
    }

    private var whiteBalancePanel: some View {
        sliderRow("White balance lock", enabled: $camera.whiteBalanceLocked,
            value: Binding(get: { camera.whiteBalanceTemperature }, set: {
                camera.whiteBalanceLocked = true
                camera.whiteBalanceTemperature = $0
            }), range: 2500...6500, center: 4500, step: 50)
    }

    private func sliderRow(_ label: String, enabled: Binding<Bool>, value: Binding<Float>,
                           range: ClosedRange<Float>, center: Float, step: Float) -> some View {
        HStack(spacing: 16) {
            Toggle(label, isOn: enabled).labelsHidden().fixedSize()
                .onChange(of: enabled.wrappedValue) { _, _ in FaceTrackHaptics.tap() }
            MagneticSlider(value: value, range: range, defaultValue: center, step: step)
                .accessibilityLabel(label + " adjustment")
        }.background(Color.clear)
    }

    private var backgroundPanel: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                backgroundChoice(.off, "Off")
                backgroundChoice(.blur, "Portrait")
                backgroundChoice(.custom, "Custom")
            }
            if showRecentBackground {
                HStack(spacing: 8) {
                    if camera.hasBackground {
                        Button("Recent") { camera.settings.background = .custom }
                            .padding(8).glassCapsule()
                        Button("Clear", role: .destructive) { camera.clearBackground() }
                            .padding(8).glassCapsule()
                    }
                    Button("Photos") { showPhotoPicker = true }
                        .padding(8).glassCapsule().disabled(loadingPhoto)
                }
            }
        }.background(Color.clear)
    }

    private func backgroundChoice(_ mode: BackgroundMode, _ title: String) -> some View {
        Button {
            if mode == .custom {
                if camera.hasBackground { showRecentBackground.toggle() }
                else { showPhotoPicker = true }
            } else {
                camera.settings.background = mode; showRecentBackground = false
            }
        } label: {
            Text(title).font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 48)
                .glassCapsule()
        }.foregroundStyle(camera.settings.background == mode ? Color.blue : .white)
    }

    private var framingGrid: some View {
        GeometryReader { geometry in
            Path { path in
                for index in 1...2 {
                    let x = geometry.size.width * CGFloat(index) / 3
                    let y = geometry.size.height * CGFloat(index) / 3
                    path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                    path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
            }.stroke(.white.opacity(0.22), lineWidth: 0.5)
        }
    }

    private var settingsPanel: some View {
        ScrollView {
            VStack(spacing: 8) {
                Menu {
                    ForEach(camera.cameras) { choice in
                        Button(choice.name) { camera.switchCamera(choice.id) }
                    }
                } label: { settingRow("Lens", camera.cameras.first(where: { $0.id == camera.selectedCamera })?.name ?? "Front", "camera") }
                    .padding(8).liquidGlass(cornerRadius: 16)
                Menu {
                    ForEach(VideoQuality.allCases) { quality in
                        Button(quality.rawValue) { camera.settings.quality = quality }
                    }
                } label: { settingRow("Quality", camera.settings.quality.rawValue, "sparkles.tv") }
                    .padding(8).liquidGlass(cornerRadius: 16).disabled(camera.streaming || camera.starting)
                Toggle("Grid", isOn: $showGrid).padding(8).liquidGlass(cornerRadius: 16)
                    .onChange(of: showGrid) { _, _ in FaceTrackHaptics.tap() }
                Toggle("Mirror selfie", isOn: $camera.mirrorPreview).padding(8).liquidGlass(cornerRadius: 16)
                    .onChange(of: camera.mirrorPreview) { _, _ in FaceTrackHaptics.tap() }
                Toggle("Mirror stream", isOn: $camera.settings.mirrorStream).padding(8).liquidGlass(cornerRadius: 16)
                    .onChange(of: camera.settings.mirrorStream) { _, _ in FaceTrackHaptics.tap() }
                Button {
                    withAnimation(.spring()) { showConnection.toggle() }
                } label: {
                    HStack { Text("Connect"); Spacer(); Image(systemName: "network").rotationEffect(iconAngle) }
                        .frame(minHeight: 32)
                }.padding(8).liquidGlass(cornerRadius: 16)
                if showConnection { connectionDetails }
            }.padding(.vertical, 8)
        }.frame(height: 216).padding(.horizontal, 16).background(Color.clear)
    }



    private func settingRow(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).rotationEffect(iconAngle)
            VStack(alignment: .leading, spacing: 1) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.headline).fixedSize(horizontal: false, vertical: true) }
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
        .background(Color.clear)
    }

    private func compactURLRow(_ title: String, _ url: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) { Text(title).font(.caption).foregroundStyle(.secondary); Text(url).font(.caption2.monospaced()).lineLimit(2).textSelection(.enabled) }
            Spacer()
            Button { UIPasteboard.general.string = url } label: { Image(systemName: "doc.on.doc").frame(width: 34, height: 34) }.disabled(!camera.streaming)
        }.padding(8).liquidGlass(cornerRadius: 16)
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

