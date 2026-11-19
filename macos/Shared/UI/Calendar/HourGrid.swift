import SwiftUI

/*
 * How tall an hour is on the day's timeline and the week's grid, and pinching to change it.
 */

/// A timeline's vertical geometry: how tall an hour is, and the room above midnight and below the
/// last hour so their labels aren't clipped.
struct HourGrid: Equatable {
    var hour: CGFloat
    let pad: CGFloat

    var height: CGFloat { y(CalendarDayMath.dayMinutes) + pad }

    /// Top of a time (minutes after midnight).
    func y(_ minutes: Int) -> CGFloat { pad + CGFloat(minutes) / 60 * hour }

    /// How tall a span of minutes is.
    func height(_ minutes: Int) -> CGFloat { CGFloat(minutes) / 60 * hour }

    /// The time at a height, to the minute, within the day.
    func minutes(at y: CGFloat) -> Int {
        min(max(Int(((y - pad) / hour * 60).rounded()), 0), CalendarDayMath.dayMinutes)
    }

    /// The scroll offset that puts a time (in minutes, fractions allowed) `y` points below the top
    /// of a `viewport` tall view, kept within what can scroll.
    func scrollY(keeping minutes: CGFloat, at y: CGFloat, viewport: CGFloat) -> CGFloat {
        min(max(pad + minutes / 60 * hour - y, 0), max(height - viewport, 0))
    }

    /// The hour heights a pinch moves between: down to the whole day in view, up to `most`.
    static func range(viewport: CGFloat, pad: CGFloat, most: CGFloat) -> ClosedRange<CGFloat> {
        let fit = (viewport - pad * 2) / 24
        return min(max(fit, 12), most)...most
    }
}

extension EnvironmentValues {
    /// The day's timeline geometry, at the height it's pinched to.
    @Entry var dayGrid = DayGrid.standard
}

/// Pinch on the trackpad to make hours taller or shorter, keeping the time under your fingers where
/// it is. Attach it to the content inside the scroll view, so the pinch is located on the grid.
struct HourPinch: ViewModifier {
    /// The grid as it's shown.
    let grid: HourGrid
    let range: ClosedRange<CGFloat>
    let scrollY: CGFloat
    let viewport: CGFloat
    /// The hour height, and the scroll offset that keeps the pinched time in place, as it goes.
    let onChange: (_ hour: CGFloat, _ scrollY: CGFloat) -> Void
    let onEnd: () -> Void

    /// Where the pinch began: the hour height, the time under it, and how far down the view that was.
    private struct Start {
        let hour: CGFloat
        let minutes: CGFloat
        let y: CGFloat
    }

    @State private var start: Start?

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            MagnifyGesture(minimumScaleDelta: 0)
                .onChanged { value in
                    let start = self.start ?? Start(
                        hour: grid.hour,
                        minutes: (value.startLocation.y - grid.pad) / grid.hour * 60,
                        y: value.startLocation.y - scrollY
                    )
                    self.start = start
                    let hour = min(max(start.hour * value.magnification, range.lowerBound), range.upperBound)
                    let zoomed = HourGrid(hour: hour, pad: grid.pad)
                    onChange(hour, zoomed.scrollY(keeping: start.minutes, at: start.y, viewport: viewport))
                }
                .onEnded { _ in
                    start = nil
                    onEnd()
                }
        )
    }
}
