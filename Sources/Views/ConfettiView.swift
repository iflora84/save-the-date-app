import SwiftUI

private struct ConfettiParticle {
    let x0: CGFloat
    let y0: CGFloat
    let vx: CGFloat
    let vy: CGFloat
    let width: CGFloat
    let height: CGFloat
    let spin: Double
    let color: Color
    let isRound: Bool
}

struct ConfettiView: View {
    /// Increment to fire a burst. Draws nothing while idle.
    let trigger: Int

    @State private var particles: [ConfettiParticle] = []
    @State private var startDate: Date? = nil
    @State private var burstID: Int = 0

    private let duration: TimeInterval = 2.4
    private let gravity: CGFloat = 900

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(paused: startDate == nil)) { timeline in
                Canvas { context, size in
                    guard let start = startDate else { return }
                    let t = CGFloat(timeline.date.timeIntervalSince(start))
                    if t < 0 || t > CGFloat(duration) { return }
                    let alpha = max(0, 1 - Double(t) / duration)
                    for p in particles {
                        let x = p.x0 + p.vx * t
                        let y = p.y0 + p.vy * t + 0.5 * gravity * t * t
                        var ctx = context
                        ctx.opacity = alpha
                        ctx.translateBy(x: x, y: y)
                        ctx.rotate(by: Angle(radians: p.spin * Double(t)))
                        let rect = CGRect(x: -p.width / 2, y: -p.height / 2, width: p.width, height: p.height)
                        if p.isRound {
                            ctx.fill(Path(ellipseIn: rect), with: .color(p.color))
                        } else {
                            ctx.fill(Path(rect), with: .color(p.color))
                        }
                    }
                }
            }
            .onChange(of: trigger) { _, _ in
                fire(in: proxy.size)
            }
        }
        .sensoryFeedback(.success, trigger: trigger)
    }

    private func fire(in size: CGSize) {
        let originX = size.width / 2
        let originY = size.height * 0.35
        var made: [ConfettiParticle] = []
        for _ in 0..<90 {
            let color = Theme.confettiColors.randomElement() ?? .white
            made.append(ConfettiParticle(
                x0: originX + CGFloat.random(in: -40...40),
                y0: originY,
                vx: CGFloat.random(in: -380...380),
                vy: CGFloat.random(in: -760...(-260)),
                width: CGFloat.random(in: 6...12),
                height: CGFloat.random(in: 8...16),
                spin: Double.random(in: -8...8),
                color: color,
                isRound: Bool.random()))
        }
        particles = made
        startDate = Date()
        burstID += 1
        let thisBurst = burstID
        let settleNanoseconds = UInt64((duration + 0.2) * 1_000_000_000)
        Task {
            try? await Task.sleep(nanoseconds: settleNanoseconds)
            if burstID == thisBurst {
                startDate = nil
                particles = []
            }
        }
    }
}

extension View {
    func confetti(trigger: Int) -> some View {
        return overlay {
            ConfettiView(trigger: trigger)
                .allowsHitTesting(false)
                .ignoresSafeArea()
        }
    }
}
