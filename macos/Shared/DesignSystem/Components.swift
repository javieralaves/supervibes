import SwiftUI

/*
 * Building blocks matching the web app's components. Each notes the Tailwind it stands in for,
 * so the two can be compared side by side.
 */

// MARK: - Card

/// `rounded-2xl border border-card-border bg-card p-6`
struct Card<Content: View>: View {
    var padding: CGFloat = 24
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
    }
}

/// A settings card's heading: title and description on the left, a status on the right.
struct CardHeader<Status: View>: View {
    let title: String
    let description: String
    @ViewBuilder var status: Status

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).appText(.base, .semibold, tracking: -0.01)
                    .foregroundStyle(Theme.foreground)
                Text(description).appText(.sm)
                    .foregroundStyle(Theme.muted)
                    // Wraps rather than truncating when the card is short of height.
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            status.padding(.top, 2)
        }
        .padding(.bottom, 20)
    }
}

extension CardHeader where Status == EmptyView {
    init(title: String, description: String) {
        self.init(title: title, description: description) { EmptyView() }
    }
}

// MARK: - Save status

/// "Saving…", ✓ Saved, or an error, as the web settings cards show it.
struct SaveStatusView: View {
    enum State: Equatable {
        case saving, saved
        case failed(String)
    }

    let state: State

    var body: some View {
        switch state {
        case .saving:
            Text("Saving…").appText(.xs, .medium).foregroundStyle(Theme.muted)
        case .saved:
            HStack(spacing: 4) {
                Icon.tick.image(size: 13)
                Text("Saved").appText(.xs, .medium)
            }
            .foregroundStyle(Theme.muted)
        case .failed(let message):
            Text(message).appText(.xs, .medium).foregroundStyle(Theme.danger)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Select

/// A labelled drop-down, like the web's `<select>` in a bordered field.
/// `h-11 rounded-xl border bg-card pl-3.5 pr-10 shadow-[0_1px_2px_rgb(15_17_20/0.05)]`
struct SelectField<Value: Hashable>: View {
    let label: String
    var icon: Icon?
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                icon?.image(size: 14)
                Text(label).appText(.xs, .medium)
            }
            .foregroundStyle(Theme.muted)

            Menu {
                Picker(label, selection: $selection) {
                    ForEach(options, id: \.self) { option in
                        Text(title(option)).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                HStack {
                    Text(title(selection))
                        .font(.app(15.2))
                        .monospacedDigit()
                        .foregroundStyle(Theme.foreground)
                    Spacer(minLength: 8)
                    Icon.chevronDown.image(size: 16).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.card)
                        .shadow(color: Color(nsColor: .rgb(0x0f1114, alpha: 0.05)), radius: 1, y: 1)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isHovered ? Theme.lineStrong : Theme.cardBorder)
                )
                .contentShape(.rect(cornerRadius: 12))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .onHover { isHovered = $0 }
        }
    }
}

// MARK: - Toggle group

/// A segmented choice: `inline-grid rounded-xl bg-wash p-1`, items `h-10 rounded-lg px-4`,
/// the selected one `bg-card shadow`.
struct ToggleGroup<Value: Hashable>: View {
    struct Option {
        let value: Value
        let label: String
        var detail: String?
    }

    @Binding var selection: Value
    let options: [Option]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                ToggleItem(option: option, isSelected: option.value == selection) {
                    selection = option.value
                }
            }
        }
        .padding(4)
        .background(Theme.wash, in: .rect(cornerRadius: 12))
        .fixedSize()
    }

    private struct ToggleItem: View {
        let option: Option
        let isSelected: Bool
        let action: () -> Void
        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 8) {
                    Text(option.label).foregroundStyle(isSelected || isHovered ? Theme.foreground : Theme.muted)
                    if let detail = option.detail {
                        Text(detail).monospacedDigit().foregroundStyle(Theme.muted)
                    }
                }
                .appText(.sm, .medium)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Theme.card)
                            .shadow(color: Color(nsColor: .rgb(0x0f1114, alpha: 0.08)), radius: 1, y: 1)
                    }
                }
                .contentShape(.rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
        }
    }
}

// MARK: - Page heading

/// A page's title and lead, like the Settings page's `h1` and `p`.
struct PageHeader: View {
    let title: String
    let lead: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).appText(.xl4, .semibold, tracking: -0.03)
                .foregroundStyle(Theme.foreground)
            Text(lead).appText(.base)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: 512, alignment: .leading)
        }
    }
}

// MARK: - Backdrop

/// The app window's quiet backdrop: a faint light from the top and a fine grid that fades out.
struct Backdrop: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .top) {
                // `radial-gradient(60% 100% at 50% 0%, var(--card), transparent)`, 480px tall, 90%.
                EllipticalGradient(
                    colors: [Theme.card, Theme.card.opacity(0)],
                    center: .top,
                    startRadiusFraction: 0,
                    endRadiusFraction: 0.5
                )
                .frame(width: width * 1.2, height: 960)
                .offset(y: -480)
                .frame(width: width, height: 480, alignment: .top)
                .clipped()
                .opacity(0.9)

                // 56px grid in the border colour, masked to fade out from the top, 60%.
                Canvas { context, size in
                    var path = Path()
                    var x: CGFloat = 0
                    while x <= size.width {
                        path.addRect(CGRect(x: x, y: 0, width: 1, height: size.height))
                        x += 56
                    }
                    var y: CGFloat = 0
                    while y <= size.height {
                        path.addRect(CGRect(x: 0, y: y, width: size.width, height: 1))
                        y += 56
                    }
                    context.fill(path, with: .color(Theme.cardBorder))
                }
                .mask {
                    EllipticalGradient(
                        colors: [.black, .clear],
                        center: .top,
                        startRadiusFraction: 0,
                        endRadiusFraction: 0.5
                    )
                    .frame(width: width * 1.4, height: geometry.size.height)
                }
                .opacity(0.6)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Avatar

/// The person's photo, or their initial on a wash. `h-10 w-10 rounded-full ring-1 ring-card-border`
struct Avatar: View {
    let name: String
    let imageURL: URL?
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let imageURL {
                AsyncImage(url: imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initial
                }
            } else {
                initial
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay(Circle().strokeBorder(Theme.cardBorder))
    }

    private var initial: some View {
        Text(name.prefix(1)).appText(.sm, .semibold)
            .foregroundStyle(Theme.foreground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.wash)
    }
}

// MARK: - Spinner

/// The loading mark: a faint ring with a short arc sweeping round it, in the current foreground
/// colour. `size` is the ring's diameter. Still when rendering statically, so snapshots match.
struct Spinner: View {
    let size: CGFloat
    @State private var turning = false
    @Environment(\.staticRendering) private var staticRendering

    private var lineWidth: CGFloat { max(1.5, size / 8) }

    var body: some View {
        ZStack {
            Circle().stroke(lineWidth: lineWidth).opacity(0.2)
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(turning ? 270 : -90))
                .animation(.linear(duration: 0.75).repeatForever(autoreverses: false), value: turning)
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
        .onAppear { if !staticRendering { turning = true } }
        .accessibilityLabel("Loading")
    }
}
