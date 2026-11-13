import SwiftUI
import CodeIslandCore
import AppKit

/// The expanded Apple Mail HUD card showing latest unread emails and quick actions.
struct CyberMailHUDView: View {
    @ObservedObject var mailManager: MailManager = MailManager.shared
    var appState: AppState

    @AppStorage(SettingsKey.islandUITheme) private var islandUITheme = SettingsDefaults.islandUITheme
    @AppStorage(SettingsKey.musicHUDProgressColor) private var musicHUDProgressColor = SettingsDefaults.musicHUDProgressColor
    @State private var hoveredMailId: Int? = nil

    init(appState: AppState) {
        self.appState = appState
    }

    private var isModernClean: Bool {
        islandUITheme == IslandUITheme.modern.rawValue
    }

    private var accentColor: Color {
        Color(red: 0.25, green: 0.52, blue: 0.96) // Royal Apple Mail Blue
    }

    public var body: some View {
        VStack(spacing: 10) {
            // Header Bar
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 6) {
                    if isModernClean {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(accentColor)
                        Text("INBOX")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                    } else {
                        PixelIcon(glyph: .email, color: Color(red: 0.0, green: 0.96, blue: 0.83), pixelSize: 1.3)
                        PixelText(text: "MAIL", color: Color(red: 0.0, green: 0.96, blue: 0.83), pixelSize: 1.1)
                    }

                    // Total Unread Badge Pill
                    HStack(spacing: 3) {
                        Text("\(mailManager.unreadCount)")
                            .font(.system(size: 9.5, weight: .bold, design: isModernClean ? .rounded : .monospaced))
                        Text("unread")
                            .font(.system(size: 8.5, weight: .medium, design: isModernClean ? .default : .monospaced))
                    }
                    .foregroundStyle(isModernClean ? accentColor : Color(red: 0.0, green: 0.96, blue: 0.83))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(
                        Capsule()
                            .fill(isModernClean ? accentColor.opacity(0.18) : Color(red: 0.0, green: 0.96, blue: 0.83).opacity(0.15))
                    )
                }

                Spacer()

                // Actions: Refresh & Launch Mail.app
                HStack(spacing: 6) {
                    Button {
                        mailManager.refresh()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9.5, weight: .semibold))
                                .rotationEffect(.degrees(mailManager.isRefreshing ? 360 : 0))
                                .animation(mailManager.isRefreshing ? Animation.linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: mailManager.isRefreshing)
                        }
                        .foregroundStyle(Color.white.opacity(0.7))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help("Refresh unread emails")

                    Button {
                        mailManager.openMailInbox()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Mail.app")
                                .font(.system(size: 9, weight: .semibold, design: isModernClean ? .rounded : .monospaced))
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 8.5, weight: .bold))
                        }
                        .foregroundStyle(Color.white.opacity(0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.white.opacity(0.10))
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Buka aplikasi Apple Mail")
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)

            // Content List or Empty State
            if mailManager.recentMails.isEmpty {
                emptyInboxView
            } else {
                mailListView
            }
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Email List View
    private var mailListView: some View {
        VStack(spacing: 7) {
            ForEach(mailManager.recentMails.prefix(4)) { mail in
                mailRow(mail)
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Single Email Card Row
    private func mailRow(_ mail: MailItem) -> some View {
        let isHovered = hoveredMailId == mail.id

        return HStack(alignment: .center, spacing: 10) {
            // Avatar
            if isModernClean {
                ZStack {
                    LinearGradient(
                        colors: mail.avatarGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Text(mail.avatarInitials)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .shadow(color: mail.avatarGradient.first?.opacity(0.35) ?? .clear, radius: 3, y: 1)
            } else {
                ZStack {
                    Color(red: 0.16, green: 0.19, blue: 0.24)
                    Text(mail.avatarInitials)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.0, green: 0.96, blue: 0.83))
                }
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(red: 0.0, green: 0.96, blue: 0.83).opacity(0.4), lineWidth: 0.8))
            }

            // Sender, Subject & Date
            VStack(alignment: .leading, spacing: 2.5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(mail.senderName)
                        .font(.system(size: 11, weight: .bold, design: isModernClean ? .rounded : .monospaced))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(mail.dateReceived)
                        .font(.system(size: 9, weight: .medium, design: isModernClean ? .default : .monospaced))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .lineLimit(1)
                }

                Text(mail.subject)
                    .font(.system(size: 10, weight: .regular, design: isModernClean ? .default : .monospaced))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // Quick Actions: Read (Checkmark) & Open (Arrow)
            HStack(spacing: 5) {
                // Mark Read Button
                Button {
                    mailManager.markAsRead(id: mail.id)
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(red: 0.12, green: 0.84, blue: 0.38))
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color(red: 0.12, green: 0.84, blue: 0.38).opacity(0.16))
                        )
                }
                .buttonStyle(.plain)
                .help("Tandai sudah dibaca")

                // Open in Mail.app Button
                Button {
                    mailManager.openInMailApp(id: mail.id)
                } label: {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isModernClean ? accentColor : Color(red: 0.0, green: 0.96, blue: 0.83))
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(isModernClean ? accentColor.opacity(0.18) : Color(red: 0.0, green: 0.96, blue: 0.83).opacity(0.16))
                        )
                }
                .buttonStyle(.plain)
                .help("Buka di Apple Mail")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: isModernClean ? 10 : 4, style: .continuous)
                .fill(isHovered ? Color.white.opacity(0.09) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: isModernClean ? 10 : 4, style: .continuous)
                .stroke(isHovered ? (isModernClean ? accentColor.opacity(0.4) : Color(red: 0.0, green: 0.96, blue: 0.83).opacity(0.4)) : Color.white.opacity(0.06), lineWidth: 0.8)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                hoveredMailId = hovering ? mail.id : nil
            }
        }
        .onTapGesture {
            mailManager.openInMailApp(id: mail.id)
        }
    }

    // MARK: - Empty State View (Inbox Zero)
    private var emptyInboxView: some View {
        VStack(spacing: 8) {
            Image(systemName: "envelope.open.fill")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [accentColor, Color(red: 0.12, green: 0.84, blue: 0.38)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.top, 6)

            Text("All Caught Up!")
                .font(.system(size: 13, weight: .bold, design: isModernClean ? .rounded : .monospaced))
                .foregroundStyle(Color.white)

            Text(mailManager.unreadCount == 0 ? "Kotak masuk Anda bersih • 0 email belum dibaca" : "\(mailManager.unreadCount) email unread di inbox")
                .font(.system(size: 10, weight: .medium, design: isModernClean ? .default : .monospaced))
                .foregroundStyle(Color.white.opacity(0.55))

            Button {
                mailManager.openMailInbox()
            } label: {
                HStack(spacing: 5) {
                    Text("Buka Apple Mail")
                        .font(.system(size: 10, weight: .semibold, design: isModernClean ? .rounded : .monospaced))
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(Color.white.opacity(0.9))
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
        .padding(.vertical, 14)
    }
}
