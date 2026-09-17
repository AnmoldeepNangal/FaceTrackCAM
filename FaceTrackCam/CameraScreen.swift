import SwiftUI
import PhotosUI
import UIKit

private enum ToolPanel: String, Identifiable, CaseIterable {
    case tracking = "Tracking", background = "Background", camera = "Camera", connection = "Connect"
    var id: String { rawValue }
    var icon: String {
        switch self { case .tracking: return "viewfinder"; case .background: return "person.crop.rectangle"; case .camera: return "slider.horizontal.3"; case .connection: return "network" }
    }
    static var allCases: [ToolPanel] { [.tracking, .background, .camera] }
}

struct CameraScreen: View {
    @StateObject private var camera = CameraModel()
    @Environment(\.scenePhase) private var phase
    @State private var panel: ToolPanel?
    @State private var photo: PhotosPickerItem?
    @State private var loadingPhoto = false
    @State private var buttonAngle: Angle = .zero

    var body: some View {
        ZStack {
            preview
            VStack(spacing: 0) { topBar; Spacer(minLength: 0); controls }
                .rotationEffect(buttonAngle)
        }
        .background(Color.black).ignoresSafeArea().statusBarHidden()
        .tint(Color("mijick-background-yellow"))
        .onAppear { camera.activate(); updateButtonAngle() }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in updateButtonAngle() }
        .onChange(of: phase) { _, value in
            if value == .active { camera.activate() } else if value == .background { camera.deactivate() }
        }
        .sheet(item: $panel) { panel in
            NavigationStack {
                Form {
                    switch panel { case .tracking: trackingPanel; case .background: backgroundPanel; case .camera: cameraPanel; case .connection: connectionPanel }
                }
                .scrollContentBackground(.hidden).background(.ultraThinMaterial)
                .navigationTitle(panel.rawValue).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { self.panel = nil } } }
            }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .alert("FaceTrackCam", isPresented: Binding(get: { camera.error != nil }, set: { if !$0 { camera.error = nil } })) {
            if camera.permissionDenied { Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } }
            Button("OK", role: .cancel) { camera.error = nil }
        } message: { Text(camera.error ?? "") }
        .task(id: photo) {
            guard let selected = photo else { return }
            loadingPhoto = true; defer { if !Task.isCancelled { loadingPhoto = false } }
            do { if let data = try await selected.loadTransferable(type: Data.self), !Task.isCancelled { camera.loadBackground(data) } }
            catch { if !Task.isCancelled { camera.error = "Photo could not be loaded." } }
        }
        .overlay { if camera.dimmed { dimOverlay } }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Image(systemName: camera.battery.map { $0 <= 20 ? "battery.25" : "battery.100" } ?? "battery.100")
                .font(.system(size: 19, weight: .medium)).accessibilityLabel("Battery")
            Spacer(minLength: 0)
            Button { panel = .connection } label: {
                Image(systemName: camera.streaming ? "network" : "network.slash")
                    .font(.system(size: 19, weight: .semibold)).frame(width: 46, height: 40)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 0.7))
            }.accessibilityLabel("Connect")
            Spacer(minLength: 0)
            Button { camera.oledSaverEnabled.toggle() } label: {
                Image(systemName: camera.oledSaverEnabled ? "moon.fill" : "moon").frame(width: 44, height: 44)
            }.foregroundStyle(camera.oledSaverEnabled ? Color("mijick-background-yellow") : .white)
                .accessibilityLabel(camera.oledSaverEnabled ? "Turn OLED saver off" : "Turn OLED saver on")
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    private var preview: some View {
        ZStack {
            Color.black
            if camera.ready { ProcessedPreview(frames: camera.preview, mirrored: camera.frontCamera && camera.mirrorPreview != camera.settings.mirrorStream) }
            else { Image(systemName: camera.permissionDenied ? "camera.fill" : "camera").font(.largeTitle).foregroundStyle(.secondary) }
        }.clipped().frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                ForEach(ToolPanel.allCases) { tool in
                    Button { panel = tool } label: {
                        Image(systemName: tool.icon).font(.system(size: 18, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 44)
                    }.foregroundStyle(tool == .tracking && camera.settings.tracking ? Color("mijick-background-yellow") : .white).accessibilityLabel(tool.rawValue)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.7))
            HStack {
                MijickRoundButton(icon: "mijick-icon-light", active: camera.torch, label: "Toggle torch") { camera.toggleTorch() }
                    .disabled(!camera.ready || !camera.hasTorch).opacity(camera.hasTorch ? 1 : 0.3)
                Spacer()
                StreamButton(active: camera.streaming, starting: camera.starting) { camera.toggleStream() }
                    .disabled(!camera.ready && !camera.streaming && !camera.starting)
                Spacer()
                MijickRoundButton(icon: "mijick-icon-change-camera", label: "Switch camera") { camera.flipCamera() }.disabled(!camera.ready)
            }
        }.padding(.top, 10).padding(.bottom, 26).padding(.horizontal, 24)
    }

    private var trackingPanel: some View {
        Section {
            Toggle("Face follow", isOn: $camera.settings.tracking)
            LabeledContent("Framing", value: String(format: "%.1f×", camera.settings.intensity))
            Slider(value: $camera.settings.intensity, in: 0.8...2.2)
        } footer: { Text("Keeps your face, shoulders, chest, and headwear in frame.") }
    }

    private var backgroundPanel: some View {
        Section {
            Picker("Mode", selection: $camera.settings.background) { Text("Off").tag(BackgroundMode.off); Text("Blur").tag(BackgroundMode.blur); if camera.hasBackground { Text("Photo").tag(BackgroundMode.custom) } }.pickerStyle(.segmented)
            PhotosPicker(selection: $photo, matching: .images) { Label(loadingPhoto ? "Loading…" : "Choose photo", systemImage: "photo") }.disabled(loadingPhoto)
            if camera.hasBackground { Button("Remove photo", role: .destructive) { camera.clearBackground(); photo = nil } }
        }
    }

    private var cameraPanel: some View {
        Group {
            Section("Lens") {
                Picker("Lens", selection: Binding(get: { camera.selectedCamera }, set: camera.switchCamera)) { ForEach(camera.cameras) { Text($0.name).tag($0.id) } }
                Picker("Quality", selection: $camera.settings.quality) { ForEach(VideoQuality.allCases) { Text($0.rawValue).tag($0) } }.disabled(camera.streaming || camera.starting)
            }
            Section("Preview") {
                LabeledContent("Frame", value: "\(Int(camera.settings.outputSize.width)) × \(Int(camera.settings.outputSize.height))")
                LabeledContent("Rate", value: camera.settings.quality.frameRate == 24 ? "24 fps" : "30 fps")
                Toggle("Mirror selfie", isOn: $camera.mirrorPreview); Toggle("Mirror stream", isOn: $camera.settings.mirrorStream)
            }
            Section("Exposure") { Toggle("Lock", isOn: $camera.exposureLocked); Slider(value: $camera.exposure, in: -2...2, step: 0.1); Button("Reset") { camera.exposure = 0; camera.exposureLocked = false } }
        }
    }

    private var connectionPanel: some View {
        Group { Section { LabeledContent("Viewers", value: "\(camera.viewers)") }; Section("Wi-Fi") { if let url = camera.wifiURL { urlRow(url) } else { Text("Join Wi-Fi to show the URL.") } }; Section("USB") { urlRow(camera.usbURL) } }
    }

    private func urlRow(_ url: String) -> some View {
        VStack(alignment: .leading, spacing: 10) { Text(url).font(.caption.monospaced()).textSelection(.enabled); Button { UIPasteboard.general.string = url } label: { Label("Copy", systemImage: "doc.on.doc") }.disabled(!camera.streaming) }
    }

    private var dimOverlay: some View { Color.black.ignoresSafeArea().contentShape(Rectangle()).onTapGesture { camera.dimmed = false }.accessibilityLabel("OLED saver active. Tap to wake.") }

    private func updateButtonAngle() {
        switch UIDevice.current.orientation {
        case .landscapeRight: buttonAngle = .zero
        case .landscapeLeft: buttonAngle = .degrees(180)
        default: break
        }
    }
}

