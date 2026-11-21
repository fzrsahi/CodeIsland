import { afterAll, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "fs";
import { createServer } from "net";
import { tmpdir } from "os";
import { join } from "path";

// A stand-in for CodeIsland's socket — never the real one — and a HOME with
// no bridge, so nothing here can reach a running CodeIsland. The module reads
// both while loading, so they are set before the import.
const dir = mkdtempSync(join(tmpdir(), "morrow-pi-"));
const socketPath = join(dir, "island.sock");
const received: Record<string, unknown>[] = [];
const island = createServer((sock) => {
  let buf = "";
  sock.on("data", (d) => {
    buf += d;
  });
  sock.on("end", () => {
    received.push(JSON.parse(buf));
  });
});
await new Promise<void>((resolve) => island.listen(socketPath, resolve));

const saved = {
  CODEISLAND_SOCKET_PATH: process.env.CODEISLAND_SOCKET_PATH,
  HOME: process.env.HOME,
  PI_SUBAGENT_PARENT_SESSION: process.env.PI_SUBAGENT_PARENT_SESSION,
};
process.env.CODEISLAND_SOCKET_PATH = socketPath;
process.env.HOME = dir;
delete process.env.PI_SUBAGENT_PARENT_SESSION;

const {
  default: codeislandExtension,
  subagentAgentName,
  subagentParentSessionId,
} = await import("../../Sources/Morrow/Resources/morrow-pi?pi-subagent-tests");

afterAll(async () => {
  for (const [key, value] of Object.entries(saved)) {
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
  await new Promise<void>((resolve) => island.close(() => resolve()));
  rmSync(dir, { recursive: true, force: true });
});

type Handler = (event: unknown, ctx: unknown) => unknown;

/** Loads the extension against a fake pi and returns a way to fire its events. */
function loadExtension(sessionId: string, sessionName: () => string | undefined) {
  const handlers = new Map<string, Handler>();
  codeislandExtension({
    on: (name: string, handler: Handler) => {
      handlers.set(name, handler);
    },
    getSessionName: sessionName,
  } as never);
  const ctx = { cwd: "/repo", sessionManager: { getSessionId: () => sessionId } };
  return async (name: string, event: Record<string, unknown> = {}) => {
    await handlers.get(name)?.({ type: name, ...event }, ctx);
  };
}

/** Payloads for one session, once `count` of them have arrived. */
async function payloadsFor(sessionId: string, count: number) {
  const mine = () => received.filter((p) => p.session_id === sessionId);
  for (let i = 0; i < 300 && mine().length < count; i++) {
    await new Promise((r) => setTimeout(r, 10));
  }
  return mine();
}

describe("pi-subagents children (#378)", () => {
  test("a child names its parent's card and its agent on every payload", async () => {
    process.env.PI_SUBAGENT_PARENT_SESSION = " 01a15910-e6c0-75af-93e2-e9c1825affc1 ";
    let name: string | undefined;
    const fire = loadExtension("child-1", () => name);
    delete process.env.PI_SUBAGENT_PARENT_SESSION;

    // Announced with its first prompt, not at session_start: by then
    // pi-subagents has named the session and the agent is known.
    await fire("session_start", { reason: "startup" });
    name = "worker: sleep 4";
    await fire("before_agent_start", {
      prompt: "Task: sleep 4",
      systemPrompt: '<active_agent name="worker"/>\n\nYou are a worker.',
    });
    await fire("tool_call", { toolName: "bash", toolCallId: "call-1", input: { command: "sleep 4" } });
    await fire("tool_result", { toolName: "bash", toolCallId: "call-1" });
    await fire("agent_end", {
      messages: [{ role: "assistant", content: [{ type: "text", text: "done" }] }],
    });
    await fire("session_shutdown", {});

    const payloads = await payloadsFor("pi-child-1", 6);
    expect(payloads.map((p) => p.hook_event_name)).toEqual([
      "SessionStart",
      "UserPromptSubmit",
      "PreToolUse",
      "PostToolUse",
      "Stop",
      "SessionEnd",
    ]);
    for (const payload of payloads) {
      expect(payload).toMatchObject({
        _source: "pi",
        _parent_session_id: "pi-01a15910-e6c0-75af-93e2-e9c1825affc1",
        agent_type: "worker",
      });
    }
    expect(payloads[0]).toMatchObject({ session_title: "worker: sleep 4" });
    expect(payloads[1]).toMatchObject({ prompt: "Task: sleep 4" });
    expect(payloads[4]).toMatchObject({ last_assistant_message: "done" });
  });

  test("a child whose agent is unknown is still a child", async () => {
    process.env.PI_SUBAGENT_PARENT_SESSION = "parent-2";
    const fire = loadExtension("child-2", () => undefined);
    delete process.env.PI_SUBAGENT_PARENT_SESSION;

    await fire("before_agent_start", { prompt: "Task", systemPrompt: "No tag here." });
    const payloads = await payloadsFor("pi-child-2", 2);
    expect(payloads.length).toBe(2);
    for (const payload of payloads) {
      expect(payload).toMatchObject({ _parent_session_id: "pi-parent-2", agent_type: "subagent" });
    }
  });

  test("a top-level session is unchanged", async () => {
    const fire = loadExtension("top-1", () => "My session");

    await fire("session_start", { reason: "startup" });
    await fire("agent_end", { messages: [] });

    const payloads = await payloadsFor("pi-top-1", 2);
    expect(payloads.map((p) => p.hook_event_name)).toEqual(["SessionStart", "Stop"]);
    for (const payload of payloads) {
      expect("_parent_session_id" in payload).toBe(false);
      expect("agent_type" in payload).toBe(false);
    }
  });

  test("reads the parent from PI_SUBAGENT_PARENT_SESSION", () => {
    expect(subagentParentSessionId({ PI_SUBAGENT_PARENT_SESSION: "abc" })).toBe("abc");
    expect(subagentParentSessionId({ PI_SUBAGENT_PARENT_SESSION: "  " })).toBeUndefined();
    expect(subagentParentSessionId({})).toBeUndefined();
  });

  test("reads the agent from pi-subagents' system prompt tag", () => {
    expect(subagentAgentName('<active_agent name="scout"/>\n\nRecon.')).toBe("scout");
    expect(subagentAgentName('<active_agent name="a&amp;b &quot;c&quot;"/>')).toBe('a&b "c"');
    expect(subagentAgentName("You are pi.")).toBeUndefined();
    expect(subagentAgentName(undefined)).toBeUndefined();
  });
});
