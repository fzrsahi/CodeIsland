import { describe, expect, test } from "bun:test";

import { resolveSocketPath } from "../../Sources/Morrow/Resources/morrow-pi";

// #78: the Morrow rename moved the app to `/tmp/morrow-<uid>.sock`, and this
// extension kept sending to `/tmp/codeisland-<uid>.sock` — silently, because
// `socketIsOwnedByUser` refused a socket that was not there. These are the
// defaults no earlier test covered: they all set the environment variable.
describe("the socket path the extension uses", () => {
  test("is the new name when nothing is set", () => {
    expect(resolveSocketPath({}, 501, () => false)).toBe("/tmp/morrow-501.sock");
  });

  test("is the new name when both exist, because the app writes that one", () => {
    expect(resolveSocketPath({}, 501, () => true)).toBe("/tmp/morrow-501.sock");
  });

  test("is the legacy name only while the new one is absent", () => {
    const onlyLegacy = (path: string) => path === "/tmp/codeisland-501.sock";
    expect(resolveSocketPath({}, 501, onlyLegacy)).toBe("/tmp/codeisland-501.sock");
  });

  test("is the explicit override, new name before old", () => {
    expect(
      resolveSocketPath(
        { MORROW_SOCKET_PATH: "/tmp/a.sock", CODEISLAND_SOCKET_PATH: "/tmp/b.sock" },
        501,
        () => false,
      ),
    ).toBe("/tmp/a.sock");
    expect(resolveSocketPath({ CODEISLAND_SOCKET_PATH: "/tmp/b.sock" }, 501, () => false)).toBe(
      "/tmp/b.sock",
    );
  });

  test("is still something usable when the check itself throws", () => {
    const throws = () => {
      throw new Error("EACCES");
    };
    expect(resolveSocketPath({}, 501, throws)).toBe("/tmp/morrow-501.sock");
  });

  test("renders uid 0 as 0, not as an empty name", () => {
    expect(resolveSocketPath({}, 0, () => false)).toBe("/tmp/morrow-0.sock");
  });
});
