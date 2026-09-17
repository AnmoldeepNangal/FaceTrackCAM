import SwiftUI

private enum RemotePanel: String, CaseIterable, Identifiable {
    case face = "FaceTrack", background = "Background", exposure = "AE", whiteBalance = "WB", settings = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .face: "viewfinder"
        case .background: "person.crop.rectangle"
        case .exposure: "sun.max"
        case .whiteBalance: "thermometer.sun"
        case .settings: "gearshape"
        }
    }
}

private struct RemoteItem: Identifiable {
    let id: String
    let name: String
}

struct RemoteScreen: View {
    @AppStorage("appMode") private var mode = "host"
    @StateObject private var peer = PeerControl(role: .remote)
    @State private var code = ""
    @State private var panel: RemotePanel?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea().onTapGesture { withAnimation(.spring()) { panel = nil } }
            VStack(spacing: 16) {
                HStack {
                    Button { mode = "host" } label: { Label("Host", systemImage: "camera") }
                    Spacer()
                    Label(peer.authorized ? "Connected" : peer.connected ? "Pair" : "Discovering", systemImage: peer.authorized ? "wifi" : "wifi.slash")
                        .foregroundStyle(peer.authorized ? Color.green : Color.secondary)
                }.font(.subheadline.weight(.medium))
                Spacer()
                if peer.authorized {
                    if let panel { controls(panel) }
                    HStack(spacing: 8) {
                        ForEach(RemotePanel.allCases) { item in
                            Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                panel = panel == item ? nil : item
                            } } label: {
                                Image(systemName: item.symbol).font(.system(size: 18, weight: .semibold))
                                    .frame(width: 44, height: 44)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .foregroundStyle(panel == item ? .blue : .white)
                            }.accessibilityLabel(item.rawValue)
                        }
                    }
                    Button {
                        peer.command("stream", value: !(peer.state["streaming"] as? Bool ?? false))
                    } label: {
                        Circle().fill(peer.state["streaming"] as? Bool == true ? Color.red : Color.white)
                            .frame(width: 64, height: 64).overlay(Circle().stroke(.white, lineWidth: 3))
                    }.accessibilityLabel(peer.state["streaming"] as? Bool == true ? "Stop stream" : "Start stream")
                } else {
                    pairing
                }
            }
            .padding(16)
        }
        .preferredColorScheme(.dark)
    }

    private var pairing: some View {
        VStack(spacing: 16) {
            Image(systemName: "iphone.gen3.radiowaves.left.and.right").font(.system(size: 44))
            Text("Connect to FacePull Host").font(.headline)
            ForEach(peer.discovered, id: \.displayName) { host in
                Button(host.displayName) { peer.connect(host) }
                    .frame(maxWidth: .infinity).padding(12).background(.ultraThinMaterial, in: Capsule())
            }
            if peer.connected && !peer.authorized {
                TextField("Six-digit code on Host", text: $code).keyboardType(.numberPad)
                    .textContentType(.oneTimeCode).padding(12).background(.ultraThinMaterial, in: Capsule())
                Button("Pair") { peer.pair(code: code) }
                    .disabled(code.count != 6)
                    .padding(12).background(.ultraThinMaterial, in: Capsule())
            }
            if let error = peer.error { Text(error).font(.caption).foregroundStyle(.orange) }
            if peer.discovered.isEmpty { Text("Keep both iPhones on the same local network.").font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func controls(_ panel: RemotePanel) -> some View {
        switch panel {
        case .face:
            VStack(spacing: 8) {
                adjustment("Face follow", action: "intensity", enabled: "tracking", range: 0.8...2.2)
                HStack {
                    choice("Lock me", selected: text("subject") == "Lock me") { peer.command("subject", value: "Lock me") }
                    choice("Auto widen", selected: text("subject") == "Auto widen") { peer.command("subject", value: "Auto widen") }
                    Button("Relock") { peer.command("relock") }.padding(10).background(.ultraThinMaterial, in: Capsule())
                }
            }
        case .background:
            VStack(spacing: 8) {
                HStack {
                    choice("Off", selected: text("background") == "Off") { peer.command("background", value: "Off") }
                    choice("Portrait", selected: text("background") == "Blur") { peer.command("background", value: "Blur") }
                }
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(items("backgrounds"), id: \.id) { item in
                            choice(item.name, selected: false) { peer.command("asset", value: item.id) }
                        }
                    }
                }.frame(maxHeight: 52)
            }
        case .exposure:
            adjustment("Exposure", action: "exposure", enabled: "exposureLocked", range: -2...2)
        case .whiteBalance:
            adjustment("White balance", action: "temperature", enabled: "whiteBalanceLocked", range: 2500...6500)
        case .settings:
            ScrollView {
                VStack(spacing: 8) {
                    Menu {
                        ForEach(items("cameras"), id: \.id) { item in
                            Button(item.name) { peer.command("lens", value: item.id) }
                        }
                    } label: { row("Lens", value: text("lens"), icon: "camera") }
                    Menu {
                        ForEach(items("qualities"), id: \.id) { item in
                            Button(item.name) { peer.command("quality", value: item.id) }
                        }
                    } label: { row("Quality", value: text("quality"), icon: "video") }
                    Toggle("Mirror stream", isOn: Binding(get: { peer.state["mirror"] as? Bool ?? false },
                        set: { peer.command("mirror", value: $0) })).padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    ForEach(items("presets"), id: \.id) { item in
                        Button { peer.command("preset", value: item.id) } label: { row(item.name, value: "Apply", icon: "slider.horizontal.3") }
                    }
                }
            }.frame(maxHeight: 240)
        }
    }

    private func adjustment(_ title: String, action: String, enabled: String, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 16) {
            Toggle(title, isOn: Binding(get: { peer.state[enabled] as? Bool ?? false },
                set: { peer.command(enabled, value: $0) })).labelsHidden()
            Slider(value: Binding(get: { (peer.state[action] as? NSNumber)?.doubleValue ?? range.lowerBound },
                set: { peer.command(action, value: String(format: "%.2f", $0)) }), in: range)
        }.padding(12).background(.ultraThinMaterial, in: Capsule())
    }

    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.subheadline.weight(.medium)).padding(12)
            .foregroundStyle(selected ? Color.blue : Color.white).background(.ultraThinMaterial, in: Capsule()) }
    }

    private func row(_ title: String, value: String, icon: String) -> some View {
        HStack { Image(systemName: icon); Text(title); Spacer(); Text(value).foregroundStyle(.secondary) }
            .padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func text(_ key: String) -> String { peer.state[key] as? String ?? "" }
    private func items(_ key: String) -> [RemoteItem] {
        (peer.state[key] as? [[String: String]] ?? []).compactMap { item in
            guard let id = item["id"], let name = item["name"] else { return nil }
            return RemoteItem(id: id, name: name)
        }
    }
}

