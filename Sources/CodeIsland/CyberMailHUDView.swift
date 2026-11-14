import SwiftUI
import CodeIslandCore
import AppKit

/// The expanded Apple Mail HUD card showing latest unread emails and quick actions.
/// Adapts dynamically between Modern Clean and Retro Cyber Pixel themes, following user's color theme.
struct CyberMailHUDView: View {
    @ObservedObject var mailManager: MailManager = MailManager.shared
    var appState: AppState

    @AppStorage(SettingsKey.islandUITheme) private var islandUITheme = SettingsDefaults.islandUITheme
    @AppStorage(SettingsKey.musicHUDProgressColor) private var musicHUDProgressColor = SettingsDefaults.musicHUDProgressColor

    init(appState: AppState) {
        self.appState = appState
    }

    private var isRetroTheme: Bool {
        islandUITheme == IslandUITheme.pixel.rawValue
    }

    private var themeColor: Color {
        AppColorTheme.accent(for: musicHUDProgressColor, isModern: !isRetroTheme)
    }

    var body: some View {
        Group {
            if isRetroTheme {
                RetroCyberMailHUDContentView(mailManager: mailManager, themeColor: themeColor)
            } else {
                ModernCleanMailHUDContentView(mailManager: mailManager, themeColor: themeColor)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isRetroTheme)
        .animation(.easeInOut(duration: 0.22), value: musicHUDProgressColor)
    }
}

// MARK: - Modern Clean Mail HUD Theme

private struct ModernCleanMailHUDContentView: View {
    @ObservedObject var mailManager: MailManager
    let themeColor: Color
    @State private var hoveredMailId: Int? = nil

    var body: some View {
        VStack(spacing: 8) {
            // Header Bar
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(themeColor)

                    Text("INBOX")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .tracking(0.6)

                    Text("•")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.25))

                    Text("\(mailManager.unreadCount.formatted()) unread")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.48))
                }

                Spacer()

                // Minimal Refresh Icon Button (No clunky boxes)
                Button {
                    mailManager.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(mailManager.isRefreshing ? 0.95 : 0.50))
                        .rotationEffect(.degrees(mailManager.isRefreshing ? 360 : 0))
                        .animation(
                            mailManager.isRefreshing
                                ? Animation.linear(duration: 0.85).repeatForever(autoreverses: false)
                                : .default,
                            value: mailManager.isRefreshing
                        )
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Refresh unread emails")
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
                        .fill(themeColor)
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
                            .foregroundStyle(themeColor)
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
                .stroke(isHovered ? themeColor.opacity(0.35) : Color.white.opacity(0.05), lineWidth: 0.8)
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
                        colors: [themeColor, Color(red: 0.12, green: 0.84, blue: 0.38)],
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

// MARK: - Retro Cyber Pixel Mail HUD Theme

private struct RetroCyberMailHUDContentView: View {
    @ObservedObject var mailManager: MailManager
    let themeColor: Color
    @State private var hoveredMailId: Int? = nil

    var body: some View {
        VStack(spacing: 8) {
            // Header Bar: Clean Pixel Typography (No Brackets, No Border)
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 7) {
                    PixelIcon(glyph: .email, color: themeColor, pixelSize: 1.35)

                    PixelText(text: "INBOX", color: themeColor, pixelSize: 1.15)

                    Text("•")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.25))

                    Text("\(mailManager.unreadCount.formatted()) unread")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.50))
                }

                Spacer()

                // Minimal Refresh Icon Button (No clunky bracket boxes)
                Button {
                    mailManager.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(mailManager.isRefreshing ? 0.95 : 0.50))
                        .rotationEffect(.degrees(mailManager.isRefreshing ? 360 : 0))
                        .animation(
                            mailManager.isRefreshing
                                ? Animation.linear(duration: 0.85).repeatForever(autoreverses: false)
                                : .default,
                            value: mailManager.isRefreshing
                        )
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Refresh unread emails")
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)

            // Content List, Loading, or Empty State
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
            ForEach(mailManager.recentMails.prefix(4)) { mail in
                retroMailRow(mail)
            }
        }
        .padding(.horizontal, 14)
    }

    private func retroMailRow(_ mail: MailItem) -> some View {
        let isHovered = hoveredMailId == mail.id

        return HStack(alignment: .center, spacing: 9) {
            // Small subtle dot accent indicator
            Circle()
                .fill(isHovered ? themeColor : themeColor.opacity(0.5))
                .frame(width: 5, height: 5)

            // Sender & Subject in Clean Monospace (No shouting ALL-CAPS, No brackets)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(mail.senderName)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(themeColor)
                        .lineLimit(1)

                    Text("• \(mail.dateReceived)")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.35))
                }

                Text(mail.subject)
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.80))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            // Minimal Actions on Hover (No clunky bracket boxes)
            if isHovered {
                HStack(spacing: 6) {
                    Button {
                        mailManager.markAsRead(id: mail.id)
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(red: 0.12, green: 0.84, blue: 0.38))
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .buttonStyle(.plain)
                    .help("Tandai sudah dibaca")

                    Button {
                        mailManager.openInMailApp(id: mail.id)
                    } label: {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(themeColor)
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .buttonStyle(.plain)
                    .help("Buka di Apple Mail")
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? themeColor.opacity(0.08) : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isHovered ? themeColor.opacity(0.25) : Color.white.opacity(0.04), lineWidth: 0.8)
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
            Text("Checking inbox stream...")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(themeColor.opacity(0.70))
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }

    private var retroEmptyView: some View {
        VStack(spacing: 6) {
            PixelIcon(glyph: .email, color: themeColor, pixelSize: 1.6)
                .padding(.top, 4)

            Text("All Caught Up!")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(themeColor)

            Text("0 unread in inbox")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.45))
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }
}
