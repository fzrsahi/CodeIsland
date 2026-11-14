import SwiftUI
import CodeIslandCore
import AppKit

/// The expanded Apple Mail HUD card showing latest unread emails and quick actions.
/// Dispatches dynamically to Modern Clean or Retro Cyber Pixel theme.
struct CyberMailHUDView: View {
    @ObservedObject var mailManager: MailManager = MailManager.shared
    var appState: AppState

    @AppStorage(SettingsKey.islandUITheme) private var islandUITheme = SettingsDefaults.islandUITheme

    init(appState: AppState) {
        self.appState = appState
    }

    private var isRetroTheme: Bool {
        islandUITheme == IslandUITheme.pixel.rawValue
    }

    var body: some View {
        Group {
            if isRetroTheme {
                RetroCyberMailHUDContentView(mailManager: mailManager, appState: appState)
            } else {
                ModernCleanMailHUDContentView(mailManager: mailManager, appState: appState)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isRetroTheme)
    }
}

// MARK: - Modern Clean Mail HUD Theme (Apple Mail Royal Blue)

private struct ModernCleanMailHUDContentView: View {
    @ObservedObject var mailManager: MailManager
    var appState: AppState
    @State private var hoveredMailId: Int? = nil

    private let royalMailBlue = Color(red: 0.12, green: 0.53, blue: 1.0)

    var body: some View {
        VStack(spacing: 10) {
            // Header Bar
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(royalMailBlue)

                    Text("INBOX")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .tracking(0.6)

                    // Formatted Unread Count Pill
                    HStack(spacing: 4) {
                        Text("\(mailManager.unreadCount.formatted())")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                        Text("unread")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(royalMailBlue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(royalMailBlue.opacity(0.16))
                            .overlay(Capsule().stroke(royalMailBlue.opacity(0.24), lineWidth: 0.8))
                    )
                }

                Spacer()

                // Header Action Buttons
                HStack(spacing: 6) {
                    Button {
                        mailManager.refresh()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .semibold))
                                .rotationEffect(.degrees(mailManager.isRefreshing ? 360 : 0))
                                .animation(
                                    mailManager.isRefreshing
                                        ? Animation.linear(duration: 0.85).repeatForever(autoreverses: false)
                                        : .default,
                                    value: mailManager.isRefreshing
                                )
                        }
                        .foregroundStyle(Color.white.opacity(0.75))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help("Refresh unread emails")

                    Button {
                        mailManager.openMailInbox()
                    } label: {
                        HStack(spacing: 5) {
                            Text("Mail.app")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(Color.white.opacity(0.90))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4.5)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.10))
                                .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.8))
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Buka aplikasi Apple Mail")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)

            // Content List, Loading Skeleton, or Empty State
            if mailManager.recentMails.isEmpty && mailManager.isRefreshing {
                loadingSkeletonView
            } else if mailManager.recentMails.isEmpty {
                emptyInboxView
            } else {
                mailListView
            }
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
    }

    private var mailListView: some View {
        VStack(spacing: 6) {
            ForEach(mailManager.recentMails.prefix(4)) { mail in
                modernMailRow(mail)
            }
        }
        .padding(.horizontal, 14)
    }

    private func modernMailRow(_ mail: MailItem) -> some View {
        let isHovered = hoveredMailId == mail.id

        return HStack(alignment: .center, spacing: 10) {
            // Gradient Initial Avatar
            ZStack {
                LinearGradient(
                    colors: mail.avatarGradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text(mail.avatarInitials)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
            .shadow(color: mail.avatarGradient.first?.opacity(0.28) ?? .clear, radius: 4, y: 1)

            // Sender & Subject
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(mail.senderName)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)

                    Circle()
                        .fill(royalMailBlue)
                        .frame(width: 4, height: 4)

                    Text(mail.dateReceived)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.45))
                }

                Text(mail.subject)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            // Quick Actions on Hover
            if isHovered {
                HStack(spacing: 6) {
                    Button {
                        mailManager.markAsRead(id: mail.id)
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(red: 0.12, green: 0.84, blue: 0.38))
                            .padding(4)
                            .background(Circle().fill(Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                    .help("Tandai sudah dibaca")

                    Button {
                        mailManager.openInMailApp(id: mail.id)
                    } label: {
                        Image(systemName: "arrow.up.right.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(royalMailBlue)
                            .padding(4)
                            .background(Circle().fill(Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                    .help("Buka email di Apple Mail")
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isHovered ? Color.white.opacity(0.08) : Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isHovered ? royalMailBlue.opacity(0.35) : Color.white.opacity(0.05), lineWidth: 0.8)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                hoveredMailId = hovering ? mail.id : nil
            }
        }
        .onTapGesture {
            mailManager.openInMailApp(id: mail.id)
        }
    }

    private var loadingSkeletonView: some View {
        VStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.09))
                            .frame(width: 120, height: 11)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.06))
                            .frame(maxWidth: .infinity)
                            .frame(height: 10)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.02))
                )
            }
        }
        .padding(.horizontal, 14)
    }

    private var emptyInboxView: some View {
        VStack(spacing: 8) {
            Image(systemName: "envelope.open.fill")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [royalMailBlue, Color(red: 0.12, green: 0.84, blue: 0.38)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.top, 4)

            Text("All Caught Up!")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)

            Text(mailManager.unreadCount == 0 ? "Kotak masuk Anda bersih • 0 email belum dibaca" : "\(mailManager.unreadCount.formatted()) email belum dibaca di inbox")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.55))

            Button {
                mailManager.openMailInbox()
            } label: {
                HStack(spacing: 5) {
                    Text("Buka Apple Mail")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(Color.white.opacity(0.92))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

// MARK: - Retro Cyber Pixel Mail HUD Theme (Cyber Electric Blue)

private struct RetroCyberMailHUDContentView: View {
    @ObservedObject var mailManager: MailManager
    var appState: AppState
    @State private var hoveredMailId: Int? = nil

    private let cyberBlue = Color(red: 0.0, green: 0.88, blue: 1.0)
    private let neonCyan = Color(red: 0.0, green: 0.96, blue: 0.83)

    var body: some View {
        VStack(spacing: 8) {
            // Retro Terminal Header
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 6) {
                    PixelIcon(glyph: .email, color: cyberBlue, pixelSize: 1.35)

                    PixelText(text: "MAIL.SYS", color: cyberBlue, pixelSize: 1.15)

                    // Pixel Terminal Badge [ 14,356 UNREAD ]
                    HStack(spacing: 3) {
                        Text("[\(mailManager.unreadCount.formatted()) UNREAD]")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(cyberBlue)
                            .cornerRadius(2)
                    }
                }

                Spacer()

                // Retro Terminal Bracket Buttons
                HStack(spacing: 6) {
                    Button {
                        mailManager.refresh()
                    } label: {
                        HStack(spacing: 3) {
                            Text(mailManager.isRefreshing ? "[SYNC...]" : "[↻ REFRESH]")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(cyberBlue)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2.5)
                                .background(Color.black)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2)
                                        .stroke(cyberBlue.opacity(0.6), lineWidth: 0.8)
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Refresh unread emails")

                    Button {
                        mailManager.openMailInbox()
                    } label: {
                        HStack(spacing: 3) {
                            Text("[MAIL.APP ↗]")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(neonCyan)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2.5)
                                .background(Color.black)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2)
                                        .stroke(neonCyan.opacity(0.6), lineWidth: 0.8)
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Buka Apple Mail")
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)

            // Retro Stream List, Loading, or Clean State
            if mailManager.recentMails.isEmpty && mailManager.isRefreshing {
                retroLoadingView
            } else if mailManager.recentMails.isEmpty {
                retroEmptyView
            } else {
                retroListView
            }
        }
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
    }

    private var retroListView: some View {
        VStack(spacing: 5) {
            ForEach(Array(mailManager.recentMails.prefix(4).enumerated()), id: \.element.id) { index, mail in
                retroMailRow(mail, index: index + 1)
            }
        }
        .padding(.horizontal, 12)
    }

    private func retroMailRow(_ mail: MailItem, index: Int) -> some View {
        let isHovered = hoveredMailId == mail.id

        return HStack(alignment: .center, spacing: 8) {
            // Index Pill [01]
            Text(String(format: "[%02d]", index))
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(isHovered ? Color.black : cyberBlue)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(isHovered ? cyberBlue : Color.white.opacity(0.06))
                .cornerRadius(2)

            // Sender & Subject Monospace
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(mail.senderName.uppercased())
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(cyberBlue)
                        .lineLimit(1)

                    Text("• \(mail.dateReceived.uppercased())")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.40))
                }

                Text(mail.subject)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            // Terminal Action Buttons
            HStack(spacing: 4) {
                Button {
                    mailManager.markAsRead(id: mail.id)
                } label: {
                    Text("[READ]")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(isHovered ? Color.black : Color(red: 0.12, green: 0.84, blue: 0.38))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(isHovered ? Color(red: 0.12, green: 0.84, blue: 0.38) : Color.black)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(Color(red: 0.12, green: 0.84, blue: 0.38).opacity(0.6), lineWidth: 0.7)
                        )
                }
                .buttonStyle(.plain)
                .help("Tandai sudah dibaca")

                Button {
                    mailManager.openInMailApp(id: mail.id)
                } label: {
                    Text("[OPEN]")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(isHovered ? Color.black : cyberBlue)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(isHovered ? cyberBlue : Color.black)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(cyberBlue.opacity(0.6), lineWidth: 0.7)
                        )
                }
                .buttonStyle(.plain)
                .help("Buka di Apple Mail")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(isHovered ? cyberBlue.opacity(0.12) : Color(red: 0.05, green: 0.08, blue: 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(isHovered ? cyberBlue : cyberBlue.opacity(0.20), lineWidth: 0.8)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.spring(response: 0.20, dampingFraction: 0.8)) {
                hoveredMailId = hovering ? mail.id : nil
            }
        }
        .onTapGesture {
            mailManager.openInMailApp(id: mail.id)
        }
    }

    private var retroLoadingView: some View {
        HStack(spacing: 6) {
            Text(">>> SCANNING INBOX PACKET STREAM...")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(cyberBlue.opacity(0.75))
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }

    private var retroEmptyView: some View {
        VStack(spacing: 6) {
            PixelIcon(glyph: .email, color: cyberBlue, pixelSize: 1.8)
                .padding(.top, 4)

            Text(">>> INBOX ZERO // ALL PACKETS CLEARED <<<")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(cyberBlue)

            Text("0 UNREAD IN STREAM")
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.50))
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }
}
