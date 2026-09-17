// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "FaceTrackCore",
    products: [.library(name: "FaceTrackCore", targets: ["FaceTrackCore"])],
    targets: [.target(name: "FaceTrackCore", path: "Core"),
              .testTarget(name: "FaceTrackCoreTests", dependencies: ["FaceTrackCore"], path: "Tests")])
