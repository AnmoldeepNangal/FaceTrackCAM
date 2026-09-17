import SwiftUI

@main
struct FaceTrackCamApp: App {
    var body: some Scene { WindowGroup { CameraScreen().preferredColorScheme(.dark) } }
}
