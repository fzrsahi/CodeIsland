using Morrow.Core;
using Morrow.Protocol;

namespace Morrow.Core.Tests;

public sealed class RawAgentEventNormalizerTests
{
    private const string CursorStopPayload = """
        {
          "conversation_id": "e1247fd5-d9a0-48ef-8457-0304606b1833",
          "generation_id": "gen-1",
          "session_id": "e1247fd5-d9a0-48ef-8457-0304606b1833",
          "model": "composer-2.5",
          "hook_event_name": "stop",
          "cursor_version": "3.25.9",
          "status": "completed"
        }
        """;

    [Theory]
    [InlineData("session.created", AgentEventType.SessionStart)]
    [InlineData("tool.execute.before", AgentEventType.ToolStart)]
    [InlineData("tool.execute.after", AgentEventType.ToolEnd)]
    [InlineData("permission.asked", AgentEventType.PermissionRequest)]
    [InlineData("session.error", AgentEventType.Error)]
    [InlineData("session.idle", AgentEventType.SessionEnd)]
    public void Normalize_OpenCodeEvent_MapsToAgentEventType(string eventName, AgentEventType expectedType)
    {
        var agentEvent = RawAgentEventNormalizer.Normalize("""
            {"session_id":"opencode-session","cwd":"C:\\work","tool_name":"bash","message":"running"}
            """, "opencode", eventName);

        Assert.Equal(AgentKind.OpenCode, agentEvent.Agent);
        Assert.Equal(expectedType, agentEvent.Type);
        Assert.Equal("opencode-session", agentEvent.SessionId);
        Assert.Equal("bash", agentEvent.ToolName);
    }

    // Cursor runs the imported Claude Code hook, which is installed without --source.
    [Fact]
    public void Normalize_UndeclaredHookWithCursorVersion_IsCursor()
    {
        var agentEvent = RawAgentEventNormalizer.Normalize(CursorStopPayload, null, "Stop");

        Assert.Equal(AgentKind.Cursor, agentEvent.Agent);
        Assert.Equal("e1247fd5-d9a0-48ef-8457-0304606b1833", agentEvent.SessionId);
        Assert.Equal(AgentEventType.SessionEnd, agentEvent.Type);
    }

    // Same as the Swift bridge: a declared source is never overridden, claude included.
    [Theory]
    [InlineData("claude", AgentKind.Claude)]
    [InlineData("codex", AgentKind.Codex)]
    public void Normalize_DeclaredSource_IsNotOverriddenByCursorVersion(string sourceTag, AgentKind expected)
    {
        var agentEvent = RawAgentEventNormalizer.Normalize(CursorStopPayload, sourceTag, "Stop");

        Assert.Equal(expected, agentEvent.Agent);
    }

    [Theory]
    [InlineData("codex", AgentKind.Codex)]
    [InlineData("claude", AgentKind.Claude)]
    public void Normalize_SupportedPayloadSource_IsNotOverriddenByCursorVersion(string payloadSource, AgentKind expected)
    {
        var agentEvent = RawAgentEventNormalizer.Normalize($$"""
            {
              "_source": "{{payloadSource}}",
              "session_id": "s-1",
              "hook_event_name": "Stop",
              "cursor_version": "3.25.9"
            }
            """);

        Assert.Equal(expected, agentEvent.Agent);
    }

    [Theory]
    [InlineData("\"  \"")]
    [InlineData("\"\"")]
    [InlineData("null")]
    [InlineData("123")]
    public void Normalize_UndeclaredHookWithBlankOrInvalidCursorVersion_IsClaude(string cursorVersionJson)
    {
        var json = $$"""
            {
              "session_id": "c1a0de00-0000-4000-8000-000000000001",
              "hook_event_name": "Stop",
              "cursor_version": {{cursorVersionJson}}
            }
            """;

        var agentEvent = RawAgentEventNormalizer.Normalize(json);

        Assert.Equal(AgentKind.Claude, agentEvent.Agent);
    }

    // Claude Code's SessionStart carries "source": "startup", which names no agent.
    [Fact]
    public void Normalize_UndeclaredClaudeSessionStart_IsClaude()
    {
        var agentEvent = RawAgentEventNormalizer.Normalize("""
            {
              "source": "startup",
              "session_id": "claude-start-1",
              "hook_event_name": "SessionStart"
            }
            """);

        Assert.Equal(AgentKind.Claude, agentEvent.Agent);
    }

    [Fact]
    public void Normalize_SessionStartSourceStartupWithCursorVersion_IsCursor()
    {
        var agentEvent = RawAgentEventNormalizer.Normalize("""
            {
              "source": "startup",
              "session_id": "cursor-start-1",
              "hook_event_name": "SessionStart",
              "cursor_version": "3.25.9"
            }
            """);

        Assert.Equal(AgentKind.Cursor, agentEvent.Agent);
    }
}
