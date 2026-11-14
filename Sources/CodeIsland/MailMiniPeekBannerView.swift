import SwiftUI
import CodeIslandCore

/// Sleek Dynamic Island Mini-Peek Banner for incoming emails.
/// Drops down gently under the notch for ~5 seconds when a new email arrives,
/// showing sender avatar, name, and subject snippet without expanding the huge HUD card.
public struct MailMiniPeekBannerView: View {
    let mail: MailItem
    let isRetro: Bool
    let accentColor: Color
    var onOpenFull: () -> Void
    var onDismiss: () -> Void

    public init(
        mail: MailItem,
        isRetro: Bool,
        accentColor: Color,
        onOpenFull: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.mail = mail
        self.isRetro = isRetro
        self.accentColor = accentColor
        self.onOpenFull = onOpenFull
        self.onDismiss = onDismiss
    }

    public var body: some View {
        Button(action: onOpenFull) {
            HStack(spacing: 8) {
                // Sender Avatar / Pixel Circle
                if isRetro {
                    ZStack {
                        LinearGradient(
                            colors: mail.avatarGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Text(mail.avatarInitials)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 22, height: 22)
                    .clipShape(PixelCircleShape(step: 2.2))
                    .overlay(
                        PixelCircleShape(step: 2.2)
                            .stroke(Color.white.opacity(0.30), lineWidth: 1.0)
                    )
                } else {
                    ZStack {
                        LinearGradient(
                            colors: mail.avatarGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Text(mail.avatarInitials)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 22, height: 22)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.8))
                }

                // Sender & Subject Preview
                VStack(alignment: .leading, spacing: 1.5) {
                    HStack(spacing: 6) {
                        Text(mail.senderName)
                            .font(.system(size: 11, weight: .semibold, design: isRetro ? .monospaced : .rounded))
                            .foregroundStyle(accentColor)
                            .lineLimit(1)

                        Text(mail.dateReceived)
                            .font(.system(size: 9, weight: .regular, design: isRetro ? .monospaced : .rounded))
                            .foregroundStyle(Color.white.opacity(0.40))
                            .lineLimit(1)
                    }

                    Text(mail.subject)
                        .font(.system(size: 10, weight: .regular, design: isRetro ? .monospaced : .default))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                // NEW Capsule Badge
                Text("NEW")
                    .font(.system(size: 8, weight: .bold, design: isRetro ? .monospaced : .rounded))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(accentColor.opacity(0.20))
                    )
                    .foregroundStyle(accentColor)

                // Dismiss Button
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.45))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help("Tutup notifikasi")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(red: 0.08, green: 0.09, blue: 0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(accentColor.opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.5), radius: 6, y: 3)
            )
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
        }
        .buttonStyle(.plain)
    }
}
