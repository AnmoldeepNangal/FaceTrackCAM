// Adapted from Mijick/Camera at 0f02348fcc8fbbc9224c7fbf444f182dc25d0b40.
// Copyright ©2024 Mijick. Original author: Tomasz Kurylik.
// Apache-2.0; see ThirdParty/Mijick-LICENSE and NOTICE.md.
// Modified: streaming state/actions replace photo and movie capture.
import SwiftUI
import UIKit

enum FaceTrackHaptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func snap() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
}

struct MijickButtonScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

struct StreamButton: View {
    let active: Bool
    let starting: Bool
    let action: () -> Void
    var body: some View {
        Button {
            FaceTrackHaptics.tap()
            action()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: active ? 6 : 36, style: .continuous)
                    .fill(Color("mijick-background-red"))
                    .padding(active ? 20 : 4)
                Circle().stroke(Color("mijick-background-inverted"), lineWidth: 2.5)
                if starting { ProgressView().tint(.white) }
            }.frame(width: 72, height: 72)
        }
        .buttonStyle(MijickButtonScaleStyle())
        .accessibilityLabel(active || starting ? "Stop streaming" : "Start streaming")
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: active)
    }
}

struct MijickRoundButton: View {
    let icon: String
    var active = false
    let label: String
    var rotation: Angle = .zero
    let action: () -> Void
    var body: some View {
        Button {
            FaceTrackHaptics.tap()
            action()
        } label: {
            Image(icon).resizable().renderingMode(.template)
                .frame(width: 26, height: 26)
                .rotationEffect(rotation)
                .foregroundStyle(active ? Color("mijick-background-yellow") : .white)
                .frame(width: 52, height: 52)
                .background(LiquidGlassBackground().clipShape(Circle()))
                .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 0.7))
        }.buttonStyle(MijickButtonScaleStyle()).accessibilityLabel(label)
    }
}

