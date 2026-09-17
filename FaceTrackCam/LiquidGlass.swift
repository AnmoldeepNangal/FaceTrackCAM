import SwiftUI
import UIKit

extension View {
    @ViewBuilder
    func facePullGlass<S: Shape>(in shape: S, tint: Color = .clear) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay(shape.fill(tint).allowsHitTesting(false))
                .overlay(shape.stroke(.white.opacity(0.2), lineWidth: 0.5).allowsHitTesting(false))
        }
    }
}

/// A live blur plus vibrancy layer. Unlike a translucent color, this samples the
/// camera feed behind the control and keeps highlights legible as the feed changes.
struct LiquidGlassBackground: UIViewRepresentable {
    var style: UIBlurEffect.Style = .systemUltraThinMaterial

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)
        container.backgroundColor = .clear
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: style))
        blur.translatesAutoresizingMaskIntoConstraints = false
        let vibrancy = UIVisualEffectView(effect: UIVibrancyEffect(blurEffect: UIBlurEffect(style: style)))
        vibrancy.translatesAutoresizingMaskIntoConstraints = false
        let highlight = UIView(frame: .zero)
        highlight.backgroundColor = UIColor.white.withAlphaComponent(0.07)
        highlight.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(blur)
        blur.contentView.addSubview(vibrancy)
        vibrancy.contentView.addSubview(highlight)
        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            blur.topAnchor.constraint(equalTo: container.topAnchor),
            blur.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            vibrancy.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor),
            vibrancy.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor),
            vibrancy.topAnchor.constraint(equalTo: blur.contentView.topAnchor),
            vibrancy.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor),
            highlight.leadingAnchor.constraint(equalTo: vibrancy.contentView.leadingAnchor),
            highlight.trailingAnchor.constraint(equalTo: vibrancy.contentView.trailingAnchor),
            highlight.topAnchor.constraint(equalTo: vibrancy.contentView.topAnchor),
            highlight.bottomAnchor.constraint(equalTo: vibrancy.contentView.bottomAnchor)
        ])
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

