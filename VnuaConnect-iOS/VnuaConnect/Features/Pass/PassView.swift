import SwiftUI
import CoreImage.CIFilterBuiltins

/// The member's rotating, event-bound check-in pass. A new token every 45s defeats screenshots being shared.
struct PassView: View {
    @Environment(AppState.self) private var app
    let event: ClubEvent
    @State private var pass: EventPass?

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Text(app.user?.name ?? "")
                    .font(VnuaFont.font(.title2, .bold))
                Text(event.title)
                    .font(VnuaFont.font(.subheadline)).foregroundStyle(Palette.secondaryText)
                    .multilineTextAlignment(.center)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.white)
                if let pass, let img = QRCode.image(pass.token) {
                    Image(uiImage: img)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(20)
                        .accessibilityLabel("Check-in code for \(event.title)")
                } else {
                    ProgressView()
                }
            }
            .frame(width: 280, height: 280)
            .shadow(color: .black.opacity(0.08), radius: 16, y: 6)

            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                if let pass {
                    let left = max(0, Int(pass.expiresAt.timeIntervalSince(ctx.date).rounded(.up)))
                    Label("Refreshes in \(left)s", systemImage: "arrow.clockwise")
                        .font(VnuaFont.font(.footnote, .medium)).foregroundStyle(Palette.secondaryText)
                        .monospacedDigit()
                }
            }

            Text("Show this to an officer at the door. It only works for this event.")
                .font(VnuaFont.font(.footnote)).foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.top, 32)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
        .background(Palette.background)
        .navigationTitle("Check-in pass")
        .navigationBarTitleDisplayMode(.inline)
        .task { await rotate() }
    }

    private func rotate() async {
        while !Task.isCancelled {
            guard let p = await app.run({ try await app.api.issuePass(eventId: event.id) }) else {
                try? await Task.sleep(for: .seconds(3)); continue
            }
            pass = p
            let wait = max(1, p.expiresAt.timeIntervalSinceNow - 2)   // refresh slightly before expiry
            try? await Task.sleep(for: .seconds(wait))
        }
    }
}

enum QRCode {
    private static let context = CIContext()
    static func image(_ string: String) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(string.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = context.createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
