import SwiftUI

/// Notch-style island outline. Drawn in a rect that is `flare` wider on each side than the body:
/// the top corners curve outward (concave) into the screen edge, the bottom corners are round.
nonisolated struct NotchShape: Shape {
    var flare: CGFloat
    var bottomRadius: CGFloat
    /// False leaves out the top edge (for an outline that should not run along the screen edge).
    var closed = true

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(flare, bottomRadius) }
        set {
            flare = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let f = max(0, min(flare, rect.width / 4, rect.height))
        let bodyWidth = rect.width - 2 * f
        let r = max(0, min(bottomRadius, bodyWidth / 2, rect.height - f))
        let left = rect.minX + f, right = rect.maxX - f
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Left flare: from the screen edge down into the body.
        path.addQuadCurve(to: CGPoint(x: left, y: rect.minY + f), control: CGPoint(x: left, y: rect.minY))
        path.addLine(to: CGPoint(x: left, y: rect.maxY - r))
        path.addArc(tangent1End: CGPoint(x: left, y: rect.maxY), tangent2End: CGPoint(x: left + r, y: rect.maxY), radius: r)
        path.addLine(to: CGPoint(x: right - r, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: right, y: rect.maxY), tangent2End: CGPoint(x: right, y: rect.maxY - r), radius: r)
        path.addLine(to: CGPoint(x: right, y: rect.minY + f))
        // Right flare back up to the edge.
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: right, y: rect.minY))
        if closed { path.closeSubpath() }
        return path
    }
}

/// Clip for notch-style content: square top, round bottom corners.
nonisolated struct BottomRoundedRect: Shape {
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadii: RectangleCornerRadii(
            topLeading: 0, bottomLeading: radius, bottomTrailing: radius, topTrailing: 0), style: .continuous)
    }
}
