using System.Text.Json;
using Morrow.Core;

namespace Morrow.Protocol;

public static class RawAgentEventNormalizer
{
    public static AgentEvent Normalize(string json, string? sourceTag = null, string? eventTag = null)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object) throw new JsonException("Hook payload must be a JSON object.");

        var eventName = FirstString(root, "hook_event_name", "hookEventName", "eventName", "event") ?? eventTag;
        var sessionId = FirstString(root, "session_id", "sessionId", "conversationId", "conversation_id", "thread_id", "threadId")
            ?? NestedString(root, "payload", "session_id", "sessionId", "thread_id")
            ?? NestedString(root, "data", "session_id", "sessionId", "thread_id");
        var cwd = FirstString(root, "cwd", "working_directory", "workingDirectory") ?? Environment.CurrentDirectory;
        var resolvedSource = ResolveSource(root, sourceTag);
        if (string.IsNullOrWhiteSpace(sessionId))
            sessionId = $"{resolvedSource ?? "agent"}-cwd-{StableHash(cwd):x8}";

        var agent = ParseAgent(resolvedSource);
        var type = ParseEventType(eventName, root);
        var eventId = FirstString(root, "event_id", "eventId", "tool_use_id", "toolUseId", "call_id", "callId")
            ?? $"{sessionId}:{eventName ?? type.ToString()}:{DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()}";
        var text = FirstString(root, "message", "question", "prompt", "response", "reason", "error");
        var toolName = FirstString(root, "tool_name", "toolName", "tool");
        var processId = FirstInt(root, "_ppid", "ppid", "process_id", "processId");
        var terminalKind = FirstString(root, "_term_app", "terminal", "terminalKind");

        return new AgentEvent(eventId, sessionId, agent, type, DateTimeOffset.UtcNow, cwd,
            FirstString(root, "title"), text, toolName, root.Clone(), processId, terminalKind);
    }

    private static AgentEventType ParseEventType(string? value, JsonElement root)
    {
        var normalized = new string((value ?? string.Empty).Where(char.IsLetterOrDigit).ToArray()).ToLowerInvariant();
        return normalized switch
        {
            "sessionstart" => AgentEventType.SessionStart,
            "sessioncreated" => AgentEventType.SessionStart,
            "sessionend" or "sessionidle" or "stop" => AgentEventType.SessionEnd,
            "pretooluse" or "toolexecutebefore" or "toolstart" => AgentEventType.ToolStart,
            "posttooluse" or "toolexecuteafter" or "toolend" => AgentEventType.ToolEnd,
            "permissionasked" or "permissionrequest" => AgentEventType.PermissionRequest,
            "question" => AgentEventType.Question,
            "notification" when FirstString(root, "question") is not null => AgentEventType.Question,
            "sessionerror" or "error" => AgentEventType.Error,
            "heartbeat" => AgentEventType.Heartbeat,
            _ => AgentEventType.Message
        };
    }

    // Same precedence as the Swift bridge (MorrowCore Models.swift bridgeSource): a declared
    // --source wins, then a supported `_source` in the payload, then a non-blank cursor_version
    // marks a hook Cursor ran (shared/contract/hook-edge-protocol.md, rule 2). The Claude Code hook is
    // installed without --source so that Cursor running it can be told apart.
    private static string? ResolveSource(JsonElement root, string? sourceTag)
    {
        var declaredSource = string.IsNullOrWhiteSpace(sourceTag) ? null : sourceTag.Trim();
        if (declaredSource is not null) return declaredSource;

        var payloadSource = FirstString(root, "_source");
        if (payloadSource is not null && ParseAgent(payloadSource) is not AgentKind.Unknown)
            return payloadSource;

        if (FirstString(root, "cursor_version") is not null) return "cursor";

        // Like the macOS island, a hook that names no known source is Claude Code's:
        // it is the one hook installed without --source.
        var namedSource = FirstString(root, "_source", "source", "agent");
        return namedSource is not null && ParseAgent(namedSource) is not AgentKind.Unknown ? namedSource : "claude";
    }

    private static AgentKind ParseAgent(string? value) => value?.Trim().ToLowerInvariant() switch
    {
        "claude" => AgentKind.Claude, "codex" => AgentKind.Codex, "gemini" => AgentKind.Gemini,
        "cursor" or "cursor-cli" or "cursor-agent" or "cursorcli" or "cursoragent" => AgentKind.Cursor,
        "copilot" => AgentKind.Copilot, "trae" => AgentKind.Trae,
        "qoder" => AgentKind.Qoder, "factory" or "droid" => AgentKind.Factory,
        "codebuddy" => AgentKind.CodeBuddy, "opencode" => AgentKind.OpenCode, "kimi" => AgentKind.Kimi,
        "cline" => AgentKind.Cline, "pi" => AgentKind.Pi, _ => AgentKind.Unknown
    };

    private static string? FirstString(JsonElement element, params string[] names)
    {
        foreach (var name in names)
            if (element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String
                && !string.IsNullOrWhiteSpace(value.GetString())) return value.GetString();
        return null;
    }

    private static string? NestedString(JsonElement root, string objectName, params string[] names) =>
        root.TryGetProperty(objectName, out var nested) && nested.ValueKind == JsonValueKind.Object
            ? FirstString(nested, names) : null;

    private static int? FirstInt(JsonElement element, params string[] names)
    {
        foreach (var name in names)
            if (element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Number
                && value.TryGetInt32(out var number)) return number;
        return null;
    }

    private static uint StableHash(string value)
    {
        uint hash = 2166136261;
        foreach (var character in value) hash = (hash ^ character) * 16777619;
        return hash;
    }
}
