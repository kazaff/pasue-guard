import AppKit
import SwiftUI

/// Shared by real covers and the draft gallery; readability belongs to the local panel.
struct BreakBackdrop: View {
    let image: CGImage?
    let reduceVisualStimulation: Bool
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.035, green: 0.05, blue: 0.08)
                if let image, !reduceVisualStimulation {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }
            }
        }
    }
}

@MainActor enum BreakTypography {
    static func countdown(size: CGFloat) -> Font {
        NSFont(name: "DINCondensed-Bold", size: size) != nil
            ? .custom("DINCondensed-Bold", size: size) : .system(size: size, weight: .medium, design: .monospaced)
    }
    static func message(size: CGFloat) -> Font {
        NSFont(name: "STSongti-SC-Regular", size: size) != nil
            ? .custom("STSongti-SC-Regular", size: size) : .system(size: size, design: .serif)
    }
}

struct BreakInfoPanel<Actions: View>: View {
    let countdown: String
    let message: String
    let countdownSize: CGFloat
    @ViewBuilder let actions: () -> Actions
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        VStack(spacing: 18) {
            Text("休息一下").font(.system(size: 30, weight: .semibold, design: .serif))
            Text(countdown).font(BreakTypography.countdown(size: countdownSize)).monospacedDigit()
                .accessibilityLabel("剩余休息时间 \(countdown)")
            Text(message).font(BreakTypography.message(size: 21)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            actions()
        }
        .foregroundStyle(.white)
        .padding(28)
        .frame(maxWidth: 440)
        .background {
            let shape = RoundedRectangle(cornerRadius: 24)
            if reduceTransparency {
                shape.fill(Color(red: 0.09, green: 0.12, blue: 0.15))
            } else {
                shape.fill(.regularMaterial).overlay { shape.fill(.black.opacity(0.22)) }
            }
        }
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.2), lineWidth: 1) }
        .shadow(color: .black.opacity(0.22), radius: 20, y: 8)
    }
}

/// Render the same presentation at a virtual display size, then scale the complete
/// scene into a card. No live model, actions, windows, or timer are involved.
struct BreakPreviewScene: View {
    let image: CGImage
    let aspectRatio: Double
    let reduceVisualStimulation: Bool
    var body: some View {
        GeometryReader { geometry in
            let width: CGFloat = 1280
            let height = width / aspectRatio
            ZStack {
                BreakBackdrop(image: image, reduceVisualStimulation: reduceVisualStimulation)
                BreakInfoPanel(countdown: "01:00", message: "让目光看向远处，放松肩膀，起身活动。", countdownSize: 100) { EmptyView() }
                    .padding(32)
            }
            .frame(width: width, height: height)
            .scaleEffect(geometry.size.width / width, anchor: .topLeading)
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipped()
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("休息画面示例，剩余一分钟")
    }
}
