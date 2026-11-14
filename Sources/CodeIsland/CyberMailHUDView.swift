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
                RetroCyberMailHUDContentView(mailManager: mailManager, themeColor: themeColor, appState: appState)
            } else {
                ModernCleanMailHUDContentView(mailManager: mailManager, themeColor: themeColor, appState: appState)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isRetroTheme)
        .animation(.easeInOut(duration: 0.22), value: musicHUDProgressColor)
    }
}

// MARK: - Modern Refresh Button (Smooth Single 360 Spin)

private struct ModernRefreshButton: View {
    @ObservedObject var mailManager: MailManager
    var color: Color = .white
    @State private var spinDegrees: Double = 0
    @State private var isSpinning: Bool = false

    var body: some View {
        Button {
            triggerRefresh()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(isSpinning || mailManager.isRefreshing ? 0.95 : 0.55))
                .rotationEffect(.degrees(spinDegrees))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Refresh unread emails")
    }

    private func triggerRefresh() {
        guard !isSpinning else { return }
        isSpinning = true
        mailManager.refresh()

        withAnimation(.easeInOut(duration: 0.65)) {
            spinDegrees += 360
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            isSpinning = false
        }
    }
}

// MARK: - Pixel Refresh Button (Crisp 8-Bit Discrete 90° Step Rotation)

private struct PixelRefreshButton: View {
    @ObservedObject var mailManager: MailManager
    var color: Color = .white
    @State private var discreteAngle: Double = 0
    @State private var isSpinning: Bool = false

    var body: some View {
        Button {
            triggerRefresh()
        } label: {
            PixelIcon(glyph: .refresh, color: color, pixelSize: 1.35)
                .rotationEffect(.degrees(discreteAngle))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Refresh unread emails")
    }

    private func triggerRefresh() {
        guard !isSpinning else { return }
        isSpinning = true
        mailManager.refresh()

        // 4-step discrete 90-degree 8-bit rotation: preserves razor-sharp pixel edges
        let steps: [(step: Int, angle: Double)] = [(1, 90.0), (2, 180.0), (3, 270.0), (4, 360.0)]
        for item in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(item.step) * 0.11) {
                discreteAngle = item.angle
                if item.step == 4 {
                    discreteAngle = 0
                    isSpinning = false
                }
            }
        }
    }
}

// MARK: - Modern Clean Mail HUD Theme

private struct ModernCleanMailHUDContentView: View {
    @ObservedObject var mailManager: MailManager
    let themeColor: Color
    var appState: AppState
    @State private var hoveredMailId: Int? = nil

    var body: some View {
        VStack(spacing: 8) {
            // Header Bar (No Dot between INBOX and unread)
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(themeColor)

                    Text("INBOX")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .tracking(0.6)

                    Text("\(mailManager.unreadCount.formatted()) unread")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.48))
                }

                Spacer()

                HStack(spacing: 6) {
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            appState.surface = .collapsed
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                            mailManager.triggerTestPeek()
                        }
                    } label: {
                        Image(systemName: "bell.badge")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Test animasi email masuk di notch kanan")

                    // Minimal Modern Refresh Icon Button
                    ModernRefreshButton(mailManager: mailManager, color: themeColor)
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

            // Sender & Subject (Max Line: 2, No Dot next to Recent)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(mail.senderName)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)

                    Text(mail.dateReceived)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.40))
                }

                Text(mail.subject)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineLimit(2)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Fixed Action Slot: Prevents ANY text wrap shift or vertical jump on hover
            ZStack(alignment: .trailing) {
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
            .frame(width: 52, alignment: .trailing)
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
    var appState: AppState
    @State private var hoveredMailId: Int? = nil

    var body: some View {
        VStack(spacing: 8) {
            // Header Bar: Clean Pixel Typography (No Brackets, No Dot)
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 8) {
                    PixelIcon(glyph: .email, color: themeColor, pixelSize: 1.35)

                    PixelText(text: "INBOX", color: themeColor, pixelSize: 1.15)

                    Text("\(mailManager.unreadCount.formatted()) unread")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.48))
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            appState.surface = .collapsed
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                            mailManager.triggerTestPeek()
                        }
                    } label: {
                        Text("[TEST]")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(themeColor.opacity(0.70))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .buttonStyle(.plain)
                    .help("Test animasi email masuk di notch kanan")

                    // 8-bit Pixel Refresh Button (Discrete 90° Step Rotation)
                    PixelRefreshButton(mailManager: mailManager, color: themeColor)
                }
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

        return HStack(alignment: .center, spacing: 10) {
            // 8-bit Stepped Pixel Circle Profile Avatar
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
            .frame(width: 22, height: 22)
            .clipShape(PixelCircleShape(step: 2.2))
            .overlay(
                PixelCircleShape(step: 2.2)
                    .stroke(Color.white.opacity(0.30), lineWidth: 1.0)
            )

            // Sender & Subject (Max Line: 2, No Dot next to Recent)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(mail.senderName)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(themeColor)
                        .lineLimit(1)

                    Text(mail.dateReceived)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.35))
                }

                Text(mail.subject)
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.80))
                    .lineLimit(2)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Fixed Action Slot: Prevents ANY text wrap shift or vertical jump on hover
            ZStack(alignment: .trailing) {
                if isHovered {
                    HStack(spacing: 6) {
                        Button {
                            mailManager.markAsRead(id: mail.id)
                        } label: {
                            PixelIcon(glyph: .checkmark, color: Color(red: 0.12, green: 0.84, blue: 0.38), pixelSize: 1.25)
                                .frame(width: 20, height: 20)
                                .background(Color.black.opacity(0.85))
                                .clipShape(PixelCircleShape(step: 2.0))
                                .overlay(
                                    PixelCircleShape(step: 2.0)
                                        .stroke(Color(red: 0.12, green: 0.84, blue: 0.38).opacity(0.65), lineWidth: 1.0)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Tandai sudah dibaca")

                        Button {
                            mailManager.openInMailApp(id: mail.id)
                        } label: {
                            PixelIcon(glyph: .arrowUpRight, color: themeColor, pixelSize: 1.25)
                                .frame(width: 20, height: 20)
                                .background(Color.black.opacity(0.85))
                                .clipShape(PixelCircleShape(step: 2.0))
                                .overlay(
                                    PixelCircleShape(step: 2.0)
                                        .stroke(themeColor.opacity(0.65), lineWidth: 1.0)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Buka di Apple Mail")
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: 48, alignment: .trailing)
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
