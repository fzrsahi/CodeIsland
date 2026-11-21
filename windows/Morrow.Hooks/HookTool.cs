using Morrow.Core;

namespace Morrow.Hooks;

public sealed record HookTool(
    AgentKind Agent,
    string DisplayName,
    IReadOnlyList<string> ExecutableNames,
    IReadOnlyList<string> ConfigPaths,
    string HookMarker,
    IReadOnlyList<string> Events,
    HookConfigurationFormat Format,
    int CommandTimeout,
    HookTimeoutUnit TimeoutUnit,
    string? SourceTag = null,
    bool DeclaresSource = true);

public enum HookConfigurationFormat { Claude, EventMap, Cursor, OpenCode }

// Each CLI owns its hook-schema timeout unit; JSON config values must not be converted.
public enum HookTimeoutUnit { Seconds, Milliseconds }

public sealed record ToolInstallation(
    HookTool Tool,
    string? ExecutablePath,
    string? ConfigPath,
    bool HookInstalled,
    bool IsHealthy,
    string? Problem);

public static class KnownTools
{
    public static IReadOnlyList<HookTool> All { get; } =
    [
        // Installed without --source, as on macOS: Cursor imports and runs Claude Code's hooks,
        // and only an undeclared hook lets cursor_version mark the event as Cursor's
        // (shared/contract/hook-edge-protocol.md, rule 2).
        new(AgentKind.Claude, "Claude Code", ["claude.exe", "claude.cmd", "claude"],
            [@".claude\settings.json", @".claude.json"], "morrow-claude",
            ["SessionStart", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop"], HookConfigurationFormat.Claude, 5, HookTimeoutUnit.Seconds,
            DeclaresSource: false),
        new(AgentKind.Codex, "Codex", ["codex.exe", "codex.cmd", "codex"],
            [@".codex\hooks.json", @".codex\config.json"], "morrow-codex",
            ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop"],
            HookConfigurationFormat.EventMap, 5, HookTimeoutUnit.Seconds),
        new(AgentKind.Gemini, "Gemini CLI", ["gemini.exe", "gemini.cmd", "gemini"],
            [@".gemini\settings.json", @".gemini\hooks.json"], "morrow-gemini",
            ["SessionStart", "BeforeTool", "AfterTool", "Notification", "SessionEnd"], HookConfigurationFormat.EventMap, 10000, HookTimeoutUnit.Milliseconds),
        new(AgentKind.Cursor, "Cursor", ["Cursor.exe", "cursor.exe", "cursor.cmd"],
            [@".cursor\hooks.json"], "morrow-cursor",
            ["sessionStart", "preToolUse", "postToolUse", "sessionEnd"], HookConfigurationFormat.Cursor, 5, HookTimeoutUnit.Seconds),
        new(AgentKind.OpenCode, "OpenCode", ["opencode.exe", "opencode.cmd", "opencode"],
            [@".config\opencode\opencode.json"], "morrow-opencode",
            ["session.created", "tool.execute.before", "tool.execute.after", "permission.asked", "session.error", "session.idle"],
            HookConfigurationFormat.OpenCode, 5, HookTimeoutUnit.Seconds),
        new(AgentKind.Qoder, "Qoder", ["Qoder.exe", "qoder.exe", "qoder.cmd"],
            [@".qoder\settings.json"], "morrow-qoder",
            ["SessionStart", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop"], HookConfigurationFormat.Claude, 5, HookTimeoutUnit.Seconds),
        new(AgentKind.Factory, "Factory Droid", ["droid.exe", "droid.cmd", "droid"],
            [@".factory\settings.json"], "morrow-droid",
            ["SessionStart", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop"], HookConfigurationFormat.Claude, 5, HookTimeoutUnit.Seconds, "droid"),
        new(AgentKind.CodeBuddy, "CodeBuddy", ["CodeBuddy.exe", "codebuddy.exe", "codebuddy.cmd"],
            [@".codebuddy\settings.json"], "morrow-codebuddy",
            ["SessionStart", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop"], HookConfigurationFormat.Claude, 5, HookTimeoutUnit.Seconds),
        new(AgentKind.Copilot, "GitHub Copilot CLI", ["copilot.exe", "copilot.cmd", "copilot"],
            [@".copilot\hooks\morrow.json"], "morrow-copilot",
            ["sessionStart", "preToolUse", "postToolUse", "sessionEnd"], HookConfigurationFormat.EventMap, 5, HookTimeoutUnit.Seconds)
    ];

    public static int TimeoutFor(HookTool tool, string eventName) =>
        tool.Agent == AgentKind.Codex && eventName == "PermissionRequest" ? 86400 : tool.CommandTimeout;
}
