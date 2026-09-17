import Foundation
import CoreGraphics

enum Framing {
    static func crop(in bounds: CGRect, aspect: CGFloat, face: CGRect?, intensity: CGFloat) -> CGRect {
        guard bounds.width > 0, bounds.height > 0, aspect > 0 else { return .zero }
        let maxWidth = min(bounds.width, bounds.height * aspect)
        var width = maxWidth
        var center = CGPoint(x: bounds.midX, y: bounds.midY)
        if let face {
            // Keep the whole upper body in frame. Lower intensity means more room;
            // the default is deliberately wide enough for shoulders, chest, and headwear.
            width = min(maxWidth, max(maxWidth * 0.62, face.width * bounds.width / (0.22 * max(0.8, intensity))))
            // Vision and Core Image both use a bottom-left origin.
            center = CGPoint(x: bounds.minX + face.midX * bounds.width,
                             y: bounds.minY + (face.midY + face.height * 0.18) * bounds.height)
        }
        return clamp(CGRect(x: center.x - width / 2, y: center.y - width / aspect / 2,
                            width: width, height: width / aspect), in: bounds, aspect: aspect)
    }

    static func clamp(_ rect: CGRect, in bounds: CGRect, aspect: CGFloat) -> CGRect {
        let width = max(1, min(rect.width, bounds.width, bounds.height * aspect))
        let height = width / aspect
        return CGRect(x: max(bounds.minX, min(rect.minX, bounds.maxX - width)),
                      y: max(bounds.minY, min(rect.minY, bounds.maxY - height)), width: width, height: height)
    }

    static func interpolate(_ from: CGRect, to: CGRect, amount: CGFloat) -> CGRect {
        let t = max(0, min(1, amount))
        return CGRect(x: from.minX + (to.minX - from.minX) * t,
                      y: from.minY + (to.minY - from.minY) * t,
                      width: from.width + (to.width - from.width) * t,
                      height: from.height + (to.height - from.height) * t)
    }

    static func subject(from faces: [CGRect], previous: CGRect?) -> CGRect? {
        guard let previous else { return faces.max { $0.width * $0.height < $1.width * $1.height } }
        return faces.min {
            hypot($0.midX - previous.midX, $0.midY - previous.midY) < hypot($1.midX - previous.midX, $1.midY - previous.midY)
        }
    }
}

