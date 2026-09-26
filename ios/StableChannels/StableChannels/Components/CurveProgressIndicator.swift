import SwiftUI

struct CurveProgressIndicator: View {
    enum CurveType {
        case sixPetalSpiral
        case spiralSearch
        case roseCurve
    }

    var curve: CurveType = .roseCurve
    var size: CGFloat = 64
    var tint: Color = .orange
    var strokeColor: Color?
    var particleCount: Int = 48
    var trailSpan: Double = 0.34
    var duration: Double = 4.6
    var pulseDuration: Double = 4.2
    var showTrack: Bool = true

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, canvasSize in
                let time = timeline.date.timeIntervalSinceReferenceDate
                render(context: &context, size: canvasSize, time: time)
            }
        }
        .frame(width: size, height: size)
    }

    private func render(context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        let scale = min(size.width, size.height) / 100.0

        let activePulseDuration = curve == .roseCurve ? 4.6 : pulseDuration
        let pulseAngle = (time.truncatingRemainder(dividingBy: activePulseDuration) / activePulseDuration) * (2.0 * .pi)
        let detailScale = 0.52 + ((sin(pulseAngle + 0.55) + 1.0) / 2.0) * 0.48

        let activeDuration = curve == .spiralSearch ? 7.8 : (curve == .roseCurve ? 5.4 : duration)
        let activeSpan = curve == .spiralSearch ? 0.28 : (curve == .roseCurve ? 0.32 : trailSpan)
        let activeParticles = curve == .roseCurve ? 64 : particleCount
        let progress = time.truncatingRemainder(dividingBy: activeDuration) / activeDuration

        if curve == .roseCurve {
            let rotationDuration = 28.0
            let rotationAngle = -(time.truncatingRemainder(dividingBy: rotationDuration) / rotationDuration) *
                (2.0 * .pi)
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: Angle(radians: rotationAngle))
            context.translateBy(x: -center.x, y: -center.y)
        }

        if showTrack {
            var trackPath = Path()
            let steps = curve == .roseCurve ? 240 : 120
            for step in 0...steps {
                let u = Double(step) / Double(steps)
                let pt = pointOnCurve(curve: curve, progress: u, detailScale: detailScale)
                let mapped = CGPoint(
                    x: center.x + (pt.x - 50.0) * scale,
                    y: center.y + (pt.y - 50.0) * scale
                )
                if step == 0 {
                    trackPath.move(to: mapped)
                } else {
                    trackPath.addLine(to: mapped)
                }
            }
            trackPath.closeSubpath()
            let trackColor = (strokeColor ?? tint).opacity(0.12)
            context.stroke(trackPath, with: .color(trackColor), lineWidth: max(1.0, 1.8 * scale))
        }

        for index in 0..<activeParticles {
            let tailOffset = Double(index) / Double(max(1, activeParticles - 1))
            var u = (progress - tailOffset * activeSpan).truncatingRemainder(dividingBy: 1.0)
            if u < 0 { u += 1.0 }

            let pt = pointOnCurve(curve: curve, progress: u, detailScale: detailScale)
            let mapped = CGPoint(
                x: center.x + (pt.x - 50.0) * scale,
                y: center.y + (pt.y - 50.0) * scale
            )

            let fade = pow(1.0 - tailOffset, 0.56)
            let radius = max(1.2, (0.9 + fade * 2.7) * scale)
            let opacity = 0.04 + fade * 0.96

            let particleRect = CGRect(
                x: mapped.x - radius,
                y: mapped.y - radius,
                width: radius * 2.0,
                height: radius * 2.0
            )

            context.fill(
                Path(ellipseIn: particleRect),
                with: .color(tint.opacity(opacity))
            )
        }
    }

    private func pointOnCurve(curve: CurveType, progress: Double, detailScale: Double) -> (x: Double, y: Double) {
        let t = progress * 2.0 * .pi
        switch curve {
        case .sixPetalSpiral:
            let d = 3.0 + detailScale * 0.25
            let baseX = 5.0 * cos(t) + d * cos(5.0 * t)
            let baseY = 5.0 * sin(t) - d * sin(5.0 * t)
            let s = (2.2 + detailScale * 0.45) * 1.85
            return (50.0 + baseX * s, 50.0 + baseY * s)

        case .spiralSearch:
            let angle = t * 4.0
            let radius = (8.0 + (1.0 - cos(t)) * (8.5 + detailScale * 2.4)) * 1.4
            return (50.0 + cos(angle) * radius, 50.0 + sin(angle) * radius)

        case .roseCurve:
            let a = 9.2 + detailScale * 0.6
            let r = a * (0.72 + detailScale * 0.28) * cos(5.0 * t)
            let scaleFactor = 3.25
            return (50.0 + cos(t) * r * scaleFactor, 50.0 + sin(t) * r * scaleFactor)
        }
    }
}

typealias MathCurveLoader = CurveProgressIndicator

#Preview("Math Curve Loaders") {
    HStack(spacing: 24) {
        CurveProgressIndicator(curve: .roseCurve, size: 76, tint: .orange)
        CurveProgressIndicator(curve: .sixPetalSpiral, size: 76, tint: .orange)
        CurveProgressIndicator(curve: .spiralSearch, size: 76, tint: .blue)
    }
    .padding()
}
