import SwiftUI
import PhotosUI

private enum ToolPanel: String, Identifiable, CaseIterable {
    case tracking = "Tracking", background = "Background", camera = "Camera", connection = "Connect"
    var id: String { rawValue }
    var icon: String {
        switch self { case .tracking: return "viewfinder"; case .background: return "person.crop.rectangle"; case .camera: return "slider.horizontal.3"; case .connection: return "network" }
    }
}

struct CameraScreen: View {
    @StateObject private var camera = CameraModel()
    @Environment(\.scenePhase) private var phase
    @State private var panel: ToolPanel?
    @State private var photo: PhotosPickerItem?
    @State private var loadingPhoto = false

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                topBar
                if geometry.size.width > geometry.size.height {
                    HStack(spacing: 16) { preview; controls.frame(width: 240) }.padding(.horizontal, 16)
                } else {
                    preview
                    controls.padding(.horizontal, 32).padding(.bottom, 24)
                }
            }
            .background(Color("mijick-background-primary"))
            .overlay { if camera.dimmed { dimOverlay } }
        }
        .statusBarHidden()
        .tint(Color("mijick-background-yellow"))
        .onAppear { camera.activate() }
        .onChange(of: phase) { _, value in
            if value == .active { camera.activate() }
            else if value == .background { camera.deactivate() }
        }
        .sheet(item: $panel) { panel in
            NavigationStack {
                Form {
                    switch panel {
                    case .tracking: trackingPanel
                    case .background: backgroundPanel
                    case .camera: cameraPanel
                    case .connection: connectionPanel
                    }
                }
                .navigationTitle(panel.rawValue)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { self.panel = nil } } }
            }.presentationDetents([.medium, .large])
        }
        .alert("FaceTrackCam", isPresented: Binding(get: { camera.error != nil }, set: { if !$0 { camera.error = nil } })) {
            if camera.permissionDenied {
                Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            }
            Button("OK", role: .cancel) { camera.error = nil }
        } message: { Text(camera.error ?? "") }
        .task(id: photo) {
            guard let selected = photo else { return }
            loadingPhoto = true
            defer { if !Task.isCancelled { loadingPhoto = false } }
            do {
                if let data = try await selected.loadTransferable(type: Data.self), !Task.isCancelled { camera.loadBackground(data) }
            } catch { if !Task.isCancelled { camera.error = "Photo could not be loaded: \(error.localizedDescription)" } }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Label(camera.battery.map { "\($0)%" } ?? "—", systemImage: "battery.100")
                .font(.caption.monospacedDigit())
            Spacer(minLength: 0)
            VStack(spacing: 3) {
                if let start = camera.streamStarted {
                    Text(start, style: .timer).font(.system(size: 20, weight: .medium).monospacedDigit())
                } else { Text("FACETRACK").font(.system(size: 13, weight: .semibold, design: .rounded)).tracking(2) }
                Text(camera.thermal).font(.system(size: 10)).foregroundStyle(camera.thermal.hasPrefix("Hot") || camera.thermal == "Too hot" ? Color.orange : Color.secondary)
            }
            Spacer(minLength: 0)
            Button { camera.dimmed = true } label: { Image(systemName: "moon").frame(width: 44, height: 44) }
                .foregroundStyle(.white).disabled(!camera.streaming).accessibilityLabel("Dim screen while streaming")
        }.padding(.horizontal, 20).padding(.vertical, 8)
            .background(Color("mijick-background-primary-80"))
    }

    private var preview: some View {
        ZStack {
            Color.black
            if camera.ready {
                ProcessedPreview(frames: camera.preview, mirrored: camera.frontCamera && camera.mirrorPreview != camera.settings.mirrorStream)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: camera.permissionDenied ? "camera.fill" : "camera").font(.largeTitle)
                    Text(camera.permissionDenied ? "Camera access is needed" : "Camera preview is paused").font(.headline)
                    Button(camera.permissionDenied ? "Open Settings" : "Start camera") {
                        if camera.permissionDenied, let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        else { camera.activate() }
                    }.buttonStyle(.bordered)
                }.foregroundStyle(.secondary)
            }
            VStack {
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(camera.streaming ? .red : .gray).frame(width: 6, height: 6)
                    Text(camera.streaming ? (camera.viewers == 0 ? "LIVE · WAITING FOR OBS" : "LIVE · \(camera.viewers) CONNECTED") : "PREVIEW")
                    Spacer()
                    Text("\(Int(camera.settings.format.size.width))×\(Int(camera.settings.format.size.height)) · \(camera.fps) FPS")
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .padding(12).background(.black.opacity(0.5))
            }
        }.clipped().frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controls: some View {
        VStack(spacing: 24) {
            HStack(spacing: 0) {
                ForEach(ToolPanel.allCases) { tool in
                    Button { panel = tool } label: {
                        VStack(spacing: 6) {
                            Image(systemName: tool.icon).font(.system(size: 18))
                            Text(tool.rawValue).font(.system(size: 10, weight: .medium))
                        }.frame(maxWidth: .infinity, minHeight: 48)
                    }.foregroundStyle(tool == .tracking && camera.settings.tracking ? Color("mijick-background-yellow") : .white)
                }
            }
            HStack {
                MijickRoundButton(icon: "mijick-icon-light", active: camera.torch, label: "Toggle torch") { camera.toggleTorch() }
                    .disabled(!camera.ready || !camera.hasTorch).opacity(camera.hasTorch ? 1 : 0.3)
                Spacer()
                StreamButton(active: camera.streaming, starting: camera.starting) { camera.toggleStream() }
                    .disabled(!camera.ready && !camera.streaming && !camera.starting)
                Spacer()
                MijickRoundButton(icon: "mijick-icon-change-camera", label: "Switch front and rear cameras") { camera.flipCamera() }
                    .disabled(!camera.ready)
            }
            Text(camera.streaming ? "STOP STREAM" : camera.starting ? "STARTING…" : "START STREAM")
                .font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(.secondary)
        }.padding(.top, 16)
    }

    private var trackingPanel: some View {
        Section {
            Toggle("Follow my face", isOn: $camera.settings.tracking)
            LabeledContent("Framing", value: String(format: "%.1f×", camera.settings.intensity))
            Slider(value: $camera.settings.intensity, in: 1...3).accessibilityLabel("Framing intensity")
                .disabled(!camera.settings.tracking)
        } footer: { Text("Keeps the nearest previous subject in frame. If the face leaves, the view gently widens after one second.") }
    }

    private var backgroundPanel: some View {
        Section {
            Picker("Background", selection: $camera.settings.background) {
                Text("Off").tag(BackgroundMode.off)
                Text("Blur").tag(BackgroundMode.blur)
                if camera.hasBackground { Text("Custom").tag(BackgroundMode.custom) }
            }.pickerStyle(.segmented)
            PhotosPicker(selection: $photo, matching: .images) {
                Label(loadingPhoto ? "Loading photo…" : camera.hasBackground ? "Change background photo" : "Choose background photo", systemImage: "photo")
            }.disabled(loadingPhoto)
            if camera.hasBackground { Button("Remove background", role: .destructive) { camera.clearBackground(); photo = nil } }
        } footer: { Text("The preview and OBS both include your background effect. Photos stay on your phone.") }
    }

    private var cameraPanel: some View {
        Group {
            Section("Camera") {
                Picker("Lens", selection: Binding(get: { camera.selectedCamera }, set: camera.switchCamera)) {
                    ForEach(camera.cameras) { Text($0.name).tag($0.id) }
                }.disabled(!camera.ready)
                Picker("Output", selection: $camera.settings.format) { ForEach(VideoFormat.allCases) { Text($0.rawValue).tag($0) } }
                    .disabled(camera.streaming || camera.starting)
                Toggle("Mirror selfie preview", isOn: $camera.mirrorPreview)
                Toggle("Mirror OBS output", isOn: $camera.settings.mirrorStream)
            }
            Section("Exposure") {
                Toggle("Lock exposure", isOn: $camera.exposureLocked)
                LabeledContent("Compensation", value: String(format: "%+.1f EV", camera.exposure))
                Slider(value: $camera.exposure, in: -2...2, step: 0.1).accessibilityLabel("Exposure compensation")
                Button("Reset exposure") { camera.exposure = 0; camera.exposureLocked = false }
            }
            Section { Text("Video only. Use your computer's microphone in OBS. Stop streaming before changing output dimensions.") }
        }
    }

    private var connectionPanel: some View {
        Group {
            Section {
                LabeledContent("Stream", value: camera.streaming ? "Running" : "Stopped")
                LabeledContent("Viewers", value: "\(camera.viewers)")
                Text("1. Start the stream. 2. In OBS, add a Media Source, turn off Local File, and paste a URL below. If needed, set Input Format to mpjpeg.")
            }
            Section("Wi-Fi") {
                if let url = camera.wifiURL { urlRow(url) }
                else { Text("Join Wi-Fi to show the phone's local address.") }
                Text("Keep your phone and computer on the same trusted network. Guest networks may block connections.")
            }
            Section("USB") {
                urlRow(camera.usbURL)
                Text("Connect and trust this computer, then start the included USB bridge on Windows. Keep this app open.")
            }
            Section {
                Text("URLs change whenever streaming restarts. Copy the new URL into OBS. A Browser Source can use the same URL with /view instead of /stream.mjpg.")
                Text("The phone must stay in this app while streaming. The moon button dims the screen without locking it.")
            }
        }
    }

    private func urlRow(_ url: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(url).font(.caption.monospaced()).textSelection(.enabled)
            Button { UIPasteboard.general.string = url } label: { Label("Copy OBS URL", systemImage: "doc.on.doc") }
                .disabled(!camera.streaming)
        }
    }

    private var dimOverlay: some View {
        Color.black.ignoresSafeArea().overlay {
            VStack(spacing: 12) {
                Image(systemName: "moon").font(.title)
                Text("Streaming · tap to wake").font(.caption)
            }.foregroundStyle(.gray)
        }.contentShape(Rectangle()).onTapGesture { camera.dimmed = false }
            .accessibilityLabel("Screen dimmed. Double tap to wake.").accessibilityAddTraits(.isButton)
    }
}

