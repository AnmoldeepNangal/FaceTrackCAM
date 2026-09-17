import Foundation
import UIKit
import ImageIO

struct BackgroundAsset: Codable, Identifiable {
    var id: UUID
    var favorite = false
    var url: URL { CameraLibrary.directory.appendingPathComponent(id.uuidString + ".jpg") }
    var thumbnail: UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0,
                [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 192,
                 kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

struct CameraPreset: Codable, Identifiable {
    var id = UUID()
    var name: String
    var settings: ProcessingSettings
    var cameraID: String
    var mirrorPreview: Bool
    var exposure: Float
    var exposureLocked: Bool
    var temperature: Float
    var whiteBalanceLocked: Bool
    var backgroundID: UUID?
    var oledSaver: Bool
    var grid: Bool
}

enum CameraLibrary {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FacePull", isDirectory: true)
    }
    static func load<T: Decodable>(_ name: String, fallback: T) -> T {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)),
              let value = try? JSONDecoder().decode(T.self, from: data) else { return fallback }
        return value
    }
    static func save<T: Encodable>(_ value: T, name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: directory.appendingPathComponent(name), options: .atomic)
    }
    static func stableSecret(_ key: String) -> String {
        if let saved = UserDefaults.standard.string(forKey: key) { return saved }
        let value = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        UserDefaults.standard.set(value, forKey: key)
        return value
    }
}

