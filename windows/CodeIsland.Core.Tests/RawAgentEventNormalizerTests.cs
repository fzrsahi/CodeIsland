using CodeIsland.Core;
using CodeIsland.Protocol;

namespace CodeIsland.Core.Tests;

public sealed class RawAgentEventNormalizerTests
{
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

    [Theory]
    [InlineData(null)]
    [InlineData("claude")]
    [InlineData("Claude")]
    public void Normalize_CursorPayloadWithCursorVersion_DoesNotAppearAsClaude(string? sourceTag)
    {
        var agentEvent = RawAgentEventNormalizer.Normalize("""
            {
              "conversation_id": "e1247fd5-d9a0-48ef-8457-0304606b1833",
              "generation_id": "gen-1",
              "session_id": "e1247fd5-d9a0-48ef-8457-0304606b1833",
              "model": "composer-2.5",
              "hook_event_name": "stop",
              "cursor_version": "3.25.9",
              "status": "completed"
            }
            """, sourceTag, "Stop");

        Assert.Equal(AgentKind.Cursor, agentEvent.Agent);
        Assert.Equal("e1247fd5-d9a0-48ef-8457-0304606b1833", agentEvent.SessionId);
        Assert.Equal(AgentEventType.SessionEnd, agentEvent.Type);
    }

    [Theory]
    [InlineData("\"  \"")]
    [InlineData("\"\"")]
    [InlineData("null")]
    [InlineData("123")]
    public void Normalize_ClaudeHookWithBlankOrInvalidCursorVersion_StaysClaude(string cursorVersionJson)
    {
        var json = $$"""
            {
              "session_id": "c1a0de00-0000-4000-8000-000000000001",
              "hook_event_name": "Stop",
              "cursor_version": {{cursorVersionJson}}
            }
            """;

        var agentEvent = RawAgentEventNormalizer.Normalize(json, "claude");

        Assert.Equal(AgentKind.Claude, agentEvent.Agent);
    }

    [Fact]
    public void Normalize_ExplicitNonClaudeSource_IsNotOverriddenByCursorVersion()
    {
        var agentEvent = RawAgentEventNormalizer.Normalize("""
            {
              "session_id": "codex-1",
              "hook_event_name": "Stop",
              "cursor_version": "3.25.9"
            }
            """, "codex");

        Assert.Equal(AgentKind.Codex, agentEvent.Agent);
    }
}
