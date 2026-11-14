import SwiftUI
import CodeIslandCore

/// Sleek Dynamic Island Mini-Peek Banner for incoming emails.
/// Drops down gently under the notch, with smooth curved sides (pill capsule),
/// pure true-black background (no harsh colored borders), 8-bit stepped circle avatar,
/// and pixelated dismiss button.
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
            HStack(spacing: 10) {
                // 1. Sender Avatar (8-bit Stepped Pixel Circle or Smooth Modern Circle)
                if isRetro {
                    ZStack {
                        LinearGradient(
                            colors: mail.avatarGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Text(mail.avatarInitials)
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 24, height: 24)
                    .clipShape(PixelCircleShape(step: 2.2))
                    .overlay(
                        PixelCircleShape(step: 2.2)
                            .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                    )
                } else {
                    ZStack {
                        LinearGradient(
                            colors: mail.avatarGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Text(mail.avatarInitials)
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.8))
                }

                // 2. Sender Name, Relative Time & Subject Snippet
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(isRetro ? mail.senderName.uppercased() : mail.senderName)
                            .font(.system(size: 11, weight: .bold, design: isRetro ? .monospaced : .rounded))
                            .foregroundStyle(accentColor)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        Text(mail.dateReceived.uppercased())
                            .font(.system(size: 9, weight: .medium, design: isRetro ? .monospaced : .rounded))
                            .foregroundStyle(Color.white.opacity(0.48))
                            .lineLimit(1)
                    }

                    Text(mail.subject)
                        .font(.system(size: 10, weight: .regular, design: isRetro ? .monospaced : .default))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineLimit(1)
                }

                // 3. Compact Dismiss Button (Pixel Art / Rounded)
                Button(action: onDismiss) {
                    ZStack {
                        if isRetro {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.10))
                                .frame(width: 18, height: 18)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
                                )
                        } else {
                            Circle()
                                .fill(Color.white.opacity(0.10))
                                .frame(width: 18, height: 18)
                        }

                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.60))
                    }
                }
                .buttonStyle(.plain)
                .help("Tutup notifikasi")
            }
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .padding(.vertical, 6)
            .frame(width: 345)
            // Pure Black Body with Smooth Curved Capsule Sides (No colored border!)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.70), radius: 8, y: 3)
            .padding(.bottom, 4)
        }
        .buttonStyle(.plain)
    }
}
