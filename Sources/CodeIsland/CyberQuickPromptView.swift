import SwiftUI
import AppKit
import CodeIslandCore

struct CyberQuickPromptView: View {
    var appState: AppState
    @State private var promptText: String = ""
    @State private var isSubmitting: Bool = false
    @State private var statusFeedback: String? = nil
    @FocusState private var isFieldFocused: Bool

    init(appState: AppState) {
        self.appState = appState
    }

    private var activeSession: SessionSnapshot? {
        let sid = appState.activeSessionId ?? appState.sessions.keys.sorted().first
        guard let sid else { return nil }
        return appState.sessions[sid]
    }

    private var targetAgentName: String {
        if let s = activeSession {
            let src = s.mascotSource.isEmpty ? s.source : s.mascotSource
            return src.uppercased()
        }
        return "AI AGENT"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Target telemetry badge + Close button
            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color(red: 0.0, green: 0.90, blue: 0.46))
                        .frame(width: 4.5, height: 4.5)
                    Text("DISPATCH TO: \(targetAgentName)")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.0, green: 0.90, blue: 0.46))
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.0, green: 0.90, blue: 0.46).opacity(0.12)))

                Spacer()

                Button(action: {
                    withAnimation(NotchAnimation.close) {
                        appState.surface = .collapsed
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color(white: 0.12)))
                }
                .buttonStyle(.plain)
            }

            // Glowing Prompt Input Box
            HStack(spacing: 6) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(red: 0.0, green: 0.96, blue: 0.83))

                TextField("Type instruction or prompt for active agent...", text: $promptText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white)
                    .focused($isFieldFocused)
                    .onSubmit {
                        submitPrompt()
                    }

                Button(action: { submitPrompt() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 9))
                        Text("RUN")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 3.5).fill(Color(red: 0.0, green: 0.96, blue: 0.83)))
                }
                .buttonStyle(.plain)
                .disabled(promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 4.5)
                    .fill(Color(red: 0.04, green: 0.05, blue: 0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4.5)
                            .stroke(Color(red: 0.0, green: 0.96, blue: 0.83).opacity(0.4), lineWidth: 1)
                    )
            )

            // Bottom Hints & Status Feedback
            HStack {
                if let feedback = statusFeedback {
                    Text(feedback)
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.0, green: 0.90, blue: 0.46))
                } else {
                    Text("Press Enter to send · Esc to cancel")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(red: 0.05, green: 0.06, blue: 0.08))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(red: 0.0, green: 0.96, blue: 0.83).opacity(0.3), lineWidth: 1))
        )
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFieldFocused = true
            }
        }
    }

    private func submitPrompt() {
        let text = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isSubmitting = true
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)

        // 1. If active session exists, activate terminal and paste/send prompt
        if let sid = appState.activeSessionId ?? appState.sessions.keys.sorted().first,
           let session = appState.sessions[sid] {
            statusFeedback = "Dispatched to \(session.source) terminal!"
            TerminalActivator.activate(session: session, sessionId: sid)

            // Copy to pasteboard so user can also ⌘V instantly
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)

            // Optional AppleScript keystroke
            let script = """
            tell application "System Events"
                keystroke "\(text.replacingOccurrences(of: "\"", with: "\\\""))"
                key code 36
            end tell
            """
            _ = AppleScriptRunner.osascript.evaluate(script, 1.0)
        } else {
            // General clipboard copy
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            statusFeedback = "Copied to clipboard!"
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(NotchAnimation.close) {
                appState.surface = .collapsed
            }
        }
    }
}
