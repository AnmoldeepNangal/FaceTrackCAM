import SwiftUI
import MetalKit
import CoreImage

// One latest frame is retained, even when the UI is busy or the screen is dimmed.
final class PreviewFrames {
    private let lock = NSLock()
    private var image: CIImage?
    func put(_ image: CIImage?) { lock.lock(); self.image = image; lock.unlock() }
    func latest() -> CIImage? { lock.lock(); defer { lock.unlock() }; return image }
}

struct ProcessedPreview: UIViewRepresentable {
    let frames: PreviewFrames
    let mirrored: Bool

    func makeCoordinator() -> Renderer { Renderer(frames: frames) }
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 30
        view.enableSetNeedsDisplay = false
        view.delegate = context.coordinator
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        context.coordinator.mirrored = mirrored
        return view
    }
    func updateUIView(_ view: MTKView, context: Context) { context.coordinator.mirrored = mirrored }
    static func dismantleUIView(_ view: MTKView, coordinator: Renderer) { view.isPaused = true; view.delegate = nil }

    final class Renderer: NSObject, MTKViewDelegate {
        let device = MTLCreateSystemDefaultDevice()
        let frames: PreviewFrames
        var mirrored = false
        private lazy var commandQueue = device?.makeCommandQueue()
        private lazy var context: CIContext? = device.map { CIContext(mtlDevice: $0, options: [.cacheIntermediates: false]) }
        init(frames: PreviewFrames) { self.frames = frames }
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        func draw(in view: MTKView) {
            guard var image = frames.latest(), let drawable = view.currentDrawable,
                  let command = commandQueue?.makeCommandBuffer(), let context else { return }
            if mirrored { image = image.transformed(by: .init(a: -1, b: 0, c: 0, d: 1, tx: image.extent.width, ty: 0)) }
            let size = view.drawableSize
            guard size.width > 0, size.height > 0 else { return }
            // The camera pipeline stays landscape for OBS. Rotate only the local
            // preview when the portrait-locked UI is taller than it is wide so a
            // horizontal sensor frame is shown in full instead of being cropped.
            if size.height > size.width, image.extent.width > image.extent.height {
                image = image.oriented(.right)
            }
            let scale = max(size.width / image.extent.width, size.height / image.extent.height)
            image = image.transformed(by: .init(scaleX: scale, y: scale))
            image = image.transformed(by: .init(translationX: (size.width - image.extent.width) / 2, y: (size.height - image.extent.height) / 2))
            let bounds = CGRect(origin: .zero, size: size)
            image = image.composited(over: CIImage(color: .black).cropped(to: bounds))
            context.render(image, to: drawable.texture, commandBuffer: command, bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())
            command.present(drawable); command.commit()
        }
    }
}

