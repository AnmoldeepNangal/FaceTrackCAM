import SwiftUI

@main
struct FaceTrackCamApp: App {
    @AppStorage("appMode") private var mode = "host"

    var body: some Scene {
        WindowGroup {
            Group {
                if mode == "remote" { RemoteScreen() }
                else { CameraScreen() }
            }.preferredColorScheme(.dark)
        }
    }
}

