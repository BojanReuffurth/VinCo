import SwiftUI

struct VinylView: View {
    let color: String
    @State private var angle: Double = 0

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                // ── Vinyl body ─────────────────────────────────────────
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: "#1A1A1A"), Color(hex: "#080808")],
                            center: .center, startRadius: 0, endRadius: size * 0.5
                        )
                    )

                // ── Dense grooves (95 % → 44 % radius) ────────────────
                ForEach(0..<32, id: \.self) { i in
                    Circle()
                        .stroke(Color.white.opacity(0.032), lineWidth: 0.5)
                        .scaleEffect(0.955 - Double(i) * 0.016)
                }

                // ── Subtle highlight sweep (vinyl sheen) ───────────────
                Circle()
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(stops: [
                                .init(color: .white.opacity(0.00), location: 0.0),
                                .init(color: .white.opacity(0.07), location: 0.25),
                                .init(color: .white.opacity(0.00), location: 0.5),
                                .init(color: .white.opacity(0.04), location: 0.75),
                                .init(color: .white.opacity(0.00), location: 1.0),
                            ]),
                            center: .center
                        ),
                        lineWidth: size * 0.27
                    )
                    .scaleEffect(0.69)

                // ── Outer groove separator ─────────────────────────────
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                    .scaleEffect(0.96)

                // ── Label area ─────────────────────────────────────────
                Circle()
                    .fill(Color(hex: color))
                    .scaleEffect(0.38)

                // Label inner ring texture
                Circle()
                    .stroke(Color.black.opacity(0.18), lineWidth: 1.2)
                    .scaleEffect(0.34)
                Circle()
                    .stroke(Color.black.opacity(0.10), lineWidth: 0.8)
                    .scaleEffect(0.26)

                // Label-to-groove edge ring
                Circle()
                    .stroke(Color.black.opacity(0.30), lineWidth: 1.0)
                    .scaleEffect(0.395)

                // ── Spindle hole ───────────────────────────────────────
                Circle()
                    .fill(Color.black)
                    .scaleEffect(0.045)
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    .scaleEffect(0.048)
            }
            .frame(width: size, height: size)
        }
        .rotationEffect(.degrees(angle))
        .onAppear {
            angle = 0
            withAnimation(.linear(duration: 3.6).repeatForever(autoreverses: false)) { angle = 360 }
        }
    }
}
