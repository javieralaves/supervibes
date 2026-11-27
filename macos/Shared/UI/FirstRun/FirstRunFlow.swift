import SwiftUI

/// The row of steps along the top of first run (the design's Steps): numbered marks joined by short lines. Steps done
/// are solid ink with a tick and a solid line behind them; the current one is ringed in ink with a soft halo; the ones
/// ahead are faint rings on a dashed line.
struct FirstRunSteps: View {
    /// The shared start's steps; every route ends in Your week.
    static let shared = ["Your plate", "Sorted", "What matters", "Your week"]

    let current: Int
    var steps: [String] = Self.shared

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                if index > 0 {
                    line(solid: index <= current).padding(.horizontal, 12)
                }
                HStack(spacing: 8) {
                    mark(index)
                    Text(step)
                        .font(.app(12.5, index == current ? .semibold : .medium))
                        .tracking(index == current ? -0.12 : 0)
                        .foregroundStyle(index == current ? Theme.foreground : index < current ? Theme.muted : Theme.muted.opacity(0.6))
                }
            }
        }
        .frame(height: 48)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func mark(_ index: Int) -> some View {
        if index < current {
            Icon.tickBold.image(size: 10)
                .foregroundStyle(Theme.background)
                .frame(width: 18, height: 18)
                .background(Theme.foreground, in: .circle)
        } else if index == current {
            Text("\(index + 1)")
                .font(.app(10.5, .semibold)).monospacedDigit()
                .foregroundStyle(Theme.foreground)
                .frame(width: 18, height: 18)
                .background(Theme.card, in: .circle)
                .overlay(Circle().strokeBorder(Theme.foreground, lineWidth: 1.5))
                .background(Circle().fill(Theme.foreground(0.06)).padding(-4))
        } else {
            Text("\(index + 1)")
                .font(.app(10.5, .semibold)).monospacedDigit()
                .foregroundStyle(Theme.muted.opacity(0.7))
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Theme.foreground(0.2), lineWidth: 1.5))
        }
    }

    private func line(solid: Bool) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0.75))
            path.addLine(to: CGPoint(x: 32, y: 0.75))
        }
        .stroke(
            solid ? Theme.foreground(0.4) : Theme.foreground(0.2),
            style: StrokeStyle(lineWidth: 1.5, dash: solid ? [] : [3, 3])
        )
        .frame(width: 32, height: 1.5)
    }
}

/// The frame each step of first run shares (the design's Flow): the steps row, an eyebrow, a title and a line, the
/// step's content, and a bar along the bottom with its way back and forward. Full window, no rail: the app proper
/// opens once first run is done.
struct FirstRunFlow<Content: View, Footer: View, Backdrop: View>: View {
    let step: Int
    var steps: [String] = FirstRunSteps.shared
    let eyebrow: String
    let title: String
    let subtitle: String
    /// Centres the eyebrow, title and line, for a step whose content sits in the middle of the window.
    var centered = false
    /// Space above the eyebrow, under the steps row.
    var headerTop: CGFloat = 28
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer
    /// Drawn behind everything but the footer, across the whole window.
    @ViewBuilder var backdrop: Backdrop

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                backdrop
                VStack(spacing: 0) {
                    FirstRunSteps(current: step, steps: steps)
                    VStack(alignment: centered ? .center : .leading, spacing: 0) {
                        Text(eyebrow).font(.app(13, .medium)).foregroundStyle(Theme.muted)
                        Text(title)
                            .font(.app(30, .semibold))
                            .tracking(-0.03 * 30)
                            .foregroundStyle(Theme.foreground)
                            .padding(.top, 4)
                        Text(subtitle)
                            .font(.app(15.2))
                            .lineSpacing(15.2 * 0.55 - 15.2 * 0.2)
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(centered ? .center : .leading)
                            .frame(maxWidth: centered ? 560 : 680, alignment: centered ? .center : .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                        content.padding(.top, 28)
                    }
                    .frame(maxWidth: 960, alignment: centered ? .center : .leading)
                    .padding(.horizontal, 32)
                    .padding(.top, headerTop)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            HStack(spacing: 8) { footer }
                .frame(maxWidth: 960)
                .padding(.horizontal, 32)
                .frame(height: 64)
                .frame(maxWidth: .infinity)
                .background(Theme.background.opacity(0.85))
                .overlay(alignment: .top) { Rectangle().fill(Theme.cardBorder).frame(height: 1) }
        }
        .background(Theme.background)
    }
}

extension FirstRunFlow where Backdrop == EmptyView {
    init(
        step: Int,
        steps: [String] = FirstRunSteps.shared,
        eyebrow: String,
        title: String,
        subtitle: String,
        centered: Bool = false,
        headerTop: CGFloat = 28,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.init(
            step: step, steps: steps, eyebrow: eyebrow, title: title, subtitle: subtitle, centered: centered,
            headerTop: headerTop, content: content, footer: footer, backdrop: { EmptyView() }
        )
    }
}
