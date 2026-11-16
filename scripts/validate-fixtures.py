#!/usr/bin/env python3
"""Validate CodeIsland JSON Schemas and golden fixtures (Draft 2020-12, stdlib-only)."""

from __future__ import annotations

import argparse
from datetime import datetime
import json
from pathlib import Path
import re
import sys
from typing import Any

OS_KEYS: frozenset[str] = frozenset({
    "_ppid",
    "_hook_ppid",
    "_term_bundle",
    "_term_app",
    "_tty",
    "_iterm_session",
})

ALLOWED_OS_KEYS: dict[str, frozenset[str]] = {
    "neutral": frozenset(),
    "macos": OS_KEYS,
    "linux": frozenset({"_ppid", "_hook_ppid", "_term_app", "_tty"}),
    "windows": frozenset({"_ppid", "_hook_ppid", "_term_app"}),
}

SCOPES: tuple[str, ...] = ("neutral", "macos", "linux", "windows")


def _is_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _json_equal(a: Any, b: Any) -> bool:
    if isinstance(a, bool) != isinstance(b, bool):
        return False
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(_json_equal(a[k], b[k]) for k in a)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(_json_equal(x, y) for x, y in zip(a, b))
    if _is_number(a) and _is_number(b):
        return a == b
    return type(a) is type(b) and a == b


def _matches_type(value: Any, expected: str) -> bool:
    if expected == "null":
        return value is None
    if expected == "boolean":
        return isinstance(value, bool)
    if expected == "integer":
        return _is_int(value)
    if expected == "number":
        return _is_number(value)
    if expected == "string":
        return isinstance(value, str)
    if expected == "array":
        return isinstance(value, list)
    if expected == "object":
        return isinstance(value, dict)
    raise ValueError(f"Unsupported JSON Schema type: {expected!r}")


def _is_valid_datetime(value: str) -> bool:
    if "T" not in value and "t" not in value:
        return False
    try:
        datetime.fromisoformat(value)
    except ValueError:
        return False
    return True


def _ecma_regex_search(pattern: str, value: str) -> bool:
    # JSON Schema ECMA-262 `$` matches end of string, not before a trailing newline.
    py_pattern = re.sub(r"(?<!\\)\$$", r"\\Z", pattern)
    return re.search(py_pattern, value) is not None


class SchemaRegistry:
    """Loads schemas from disk and resolves local and relative $ref pointers."""

    def __init__(self, schemas_dir: Path) -> None:
        self.schemas_dir = schemas_dir
        self.by_name: dict[str, dict[str, Any]] = {}
        self.by_id: dict[str, dict[str, Any]] = {}
        for path in sorted(schemas_dir.glob("*.json")):
            data = json.loads(path.read_text(encoding="utf-8"))
            self.by_name[path.name] = data
            schema_id = data.get("$id")
            if isinstance(schema_id, str):
                self.by_id[schema_id] = data

    def resolve_ref(self, ref: str, current_root: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
        if "#" in ref:
            uri_part, pointer = ref.split("#", 1)
        else:
            uri_part, pointer = ref, ""

        if not uri_part:
            target_root = current_root
        elif uri_part in self.by_id:
            target_root = self.by_id[uri_part]
        elif uri_part in self.by_name:
            target_root = self.by_name[uri_part]
        else:
            basename = uri_part.rsplit("/", 1)[-1]
            if basename in self.by_name:
                target_root = self.by_name[basename]
            else:
                raise KeyError(f"Unresolvable schema $ref: {ref!r}")

        node: Any = target_root
        if pointer:
            if not pointer.startswith("/"):
                raise KeyError(f"Unsupported JSON pointer in $ref: {ref!r}")
            for raw_seg in pointer[1:].split("/"):
                seg = raw_seg.replace("~1", "/").replace("~0", "~")
                if isinstance(node, dict) and seg in node:
                    node = node[seg]
                elif isinstance(node, list) and seg.isdigit() and int(seg) < len(node):
                    node = node[int(seg)]
                else:
                    raise KeyError(f"Missing pointer segment {seg!r} in $ref {ref!r}")

        if not isinstance(node, dict) and not isinstance(node, bool):
            raise TypeError(f"Resolved $ref {ref!r} is not a schema object")
        return node, target_root


class Draft202012Validator:
    """Minimal stdlib-only Draft 2020-12 JSON Schema validator."""

    def __init__(self, registry: SchemaRegistry) -> None:
        self.registry = registry

    def validate(self, instance: Any, schema: dict[str, Any] | bool) -> list[str]:
        return self._validate(instance, schema, root=schema if isinstance(schema, dict) else {}, path="$")

    def _validate(
        self,
        instance: Any,
        schema: dict[str, Any] | bool,
        root: dict[str, Any],
        path: str,
    ) -> list[str]:
        if schema is True:
            return []
        if schema is False:
            return [f"{path}: value disallowed by false schema"]

        errors: list[str] = []

        if "$ref" in schema:
            target, target_root = self.registry.resolve_ref(schema["$ref"], root)
            errors.extend(self._validate(instance, target, target_root, path))

        if "const" in schema and not _json_equal(instance, schema["const"]):
            errors.append(f"{path}: expected const {schema['const']!r}, got {instance!r}")

        if "enum" in schema and not any(_json_equal(instance, item) for item in schema["enum"]):
            errors.append(f"{path}: value {instance!r} not in enum {schema['enum']!r}")

        if "type" in schema:
            expected_types = schema["type"] if isinstance(schema["type"], list) else [schema["type"]]
            if not any(_matches_type(instance, t) for t in expected_types):
                errors.append(f"{path}: expected type {schema['type']!r}, got {type(instance).__name__} ({instance!r})")
                return errors

        if isinstance(instance, str):
            if "minLength" in schema and len(instance) < schema["minLength"]:
                errors.append(f"{path}: string length {len(instance)} < minLength {schema['minLength']}")
            if "maxLength" in schema and len(instance) > schema["maxLength"]:
                errors.append(f"{path}: string length {len(instance)} > maxLength {schema['maxLength']}")
            if "pattern" in schema and not _ecma_regex_search(schema["pattern"], instance):
                errors.append(f"{path}: string {instance!r} does not match pattern {schema['pattern']!r}")
            if schema.get("format") == "date-time" and not _is_valid_datetime(instance):
                errors.append(f"{path}: string {instance!r} is not a valid RFC3339/ISO date-time")

        if _is_number(instance):
            if "minimum" in schema and instance < schema["minimum"]:
                errors.append(f"{path}: {instance} < minimum {schema['minimum']}")
            if "maximum" in schema and instance > schema["maximum"]:
                errors.append(f"{path}: {instance} > maximum {schema['maximum']}")
            if "exclusiveMinimum" in schema and instance <= schema["exclusiveMinimum"]:
                errors.append(f"{path}: {instance} <= exclusiveMinimum {schema['exclusiveMinimum']}")
            if "exclusiveMaximum" in schema and instance >= schema["exclusiveMaximum"]:
                errors.append(f"{path}: {instance} >= exclusiveMaximum {schema['exclusiveMaximum']}")

        if isinstance(instance, list):
            if "minItems" in schema and len(instance) < schema["minItems"]:
                errors.append(f"{path}: array length {len(instance)} < minItems {schema['minItems']}")
            if "maxItems" in schema and len(instance) > schema["maxItems"]:
                errors.append(f"{path}: array length {len(instance)} > maxItems {schema['maxItems']}")
            if schema.get("uniqueItems"):
                for i in range(len(instance)):
                    for j in range(i + 1, len(instance)):
                        if _json_equal(instance[i], instance[j]):
                            errors.append(f"{path}: array items at [{i}] and [{j}] are not unique")
                            break
            if "items" in schema:
                item_schema = schema["items"]
                for idx, item in enumerate(instance):
                    errors.extend(self._validate(item, item_schema, root, f"{path}[{idx}]"))

        if isinstance(instance, dict):
            for req in schema.get("required", []):
                if req not in instance:
                    errors.append(f"{path}: missing required property {req!r}")

            props = schema.get("properties", {})
            pattern_props = schema.get("patternProperties", {})
            additional = schema.get("additionalProperties", True)

            for key, val in instance.items():
                matched = False
                key_path = f"{path}.{key}"
                if key in props:
                    matched = True
                    errors.extend(self._validate(val, props[key], root, key_path))
                for pat, pat_schema in pattern_props.items():
                    if re.search(pat, key):
                        matched = True
                        errors.extend(self._validate(val, pat_schema, root, key_path))
                if not matched:
                    if additional is False:
                        errors.append(f"{path}: additional property {key!r} is not allowed")
                    elif isinstance(additional, dict):
                        errors.extend(self._validate(val, additional, root, key_path))

        if "allOf" in schema:
            for sub in schema["allOf"]:
                errors.extend(self._validate(instance, sub, root, path))

        if "anyOf" in schema:
            sub_errors = [self._validate(instance, sub, root, path) for sub in schema["anyOf"]]
            if not any(len(errs) == 0 for errs in sub_errors):
                errors.append(f"{path}: did not match anyOf branches")

        if "oneOf" in schema:
            matches = [self._validate(instance, sub, root, path) for sub in schema["oneOf"]]
            valid_count = sum(1 for errs in matches if len(errs) == 0)
            if valid_count != 1:
                detail = "; ".join(errs[0] for errs in matches if errs)
                errors.append(f"{path}: expected exactly 1 oneOf match, got {valid_count} ({detail})")

        if "not" in schema:
            if not self._validate(instance, schema["not"], root, path):
                errors.append(f"{path}: value matched disallowed 'not' schema")

        return errors


def _optional_jsonschema_check(registry: SchemaRegistry, schema_name: str, instance: Any) -> list[str]:
    try:
        import jsonschema  # type: ignore
        import referencing  # type: ignore
        import referencing.jsonschema  # type: ignore
    except ImportError:
        return []

    resources = []
    for name, doc in registry.by_name.items():
        res = referencing.Resource.from_contents(doc, default_specification=referencing.jsonschema.DRAFT202012)
        resources.append((doc.get("$id", name), res))
        resources.append((name, res))
    ref_registry = referencing.Registry().with_resources(resources)
    validator = jsonschema.Draft202012Validator(registry.by_name[schema_name], registry=ref_registry)
    return [f"[jsonschema] {err.message}" for err in validator.iter_errors(instance)]


def strip_os_keys(forwarded: dict[str, Any] | None) -> dict[str, Any] | None:
    if forwarded is None:
        return None
    return {k: v for k, v in forwarded.items() if k not in OS_KEYS}


def check_cross_os_neutrality(fixtures_by_scope: dict[str, dict[str, dict[str, Any]]]) -> list[str]:
    errors: list[str] = []
    neutral_map = fixtures_by_scope.get("neutral", {})

    for name, neutral_doc in sorted(neutral_map.items()):
        fwd = neutral_doc["expectation"]["forwarded"]
        if isinstance(fwd, dict):
            forbidden = sorted(k for k in fwd if k in OS_KEYS)
            if forbidden:
                errors.append(f"neutral/{name}.json: contains forbidden OS keys {forbidden}")

    for scope in ("macos", "linux", "windows"):
        scope_map = fixtures_by_scope.get(scope, {})
        if not scope_map:
            continue

        if neutral_map:
            missing_in_scope = sorted(set(neutral_map) - set(scope_map))
            extra_in_scope = sorted(set(scope_map) - set(neutral_map))
            if missing_in_scope:
                errors.append(f"{scope}: missing fixtures present in neutral: {missing_in_scope}")
            if extra_in_scope:
                errors.append(f"{scope}: extra fixtures absent from neutral: {extra_in_scope}")

        allowed = ALLOWED_OS_KEYS[scope]
        for name, doc in sorted(scope_map.items()):
            fwd = doc["expectation"]["forwarded"]
            if isinstance(fwd, dict):
                disallowed = sorted(k for k in fwd if k in OS_KEYS and k not in allowed)
                if disallowed:
                    errors.append(f"{scope}/{name}.json: disallowed OS keys for {scope}: {disallowed}")

            if name in neutral_map:
                neutral_fwd = neutral_map[name]["expectation"]["forwarded"]
                stripped = strip_os_keys(fwd)
                if not _json_equal(stripped, neutral_fwd):
                    errors.append(
                        f"{scope}/{name}.json: forwarded minus OS keys does not match neutral/{name}.json"
                    )

    return errors


def validate_fixtures_dir(
    fixtures_dir: Path,
    validator: Draft202012Validator,
    registry: SchemaRegistry,
) -> tuple[int, list[str]]:
    errors: list[str] = []
    fixtures_by_scope: dict[str, dict[str, dict[str, Any]]] = {s: {} for s in SCOPES}
    fixture_schema = registry.by_name["golden-fixture.schema.json"]
    payload_schema = registry.by_name["hook-payload.schema.json"]
    file_count = 0

    for scope in SCOPES:
        scope_dir = fixtures_dir / scope
        if not scope_dir.is_dir():
            continue
        for path in sorted(scope_dir.glob("*.json")):
            file_count += 1
            try:
                doc = json.loads(path.read_text(encoding="utf-8"))
            except json.JSONDecodeError as exc:
                errors.append(f"{path}: invalid JSON: {exc}")
                continue

            errs = validator.validate(doc, fixture_schema)
            errs.extend(_optional_jsonschema_check(registry, "golden-fixture.schema.json", doc))
            if errs:
                errors.extend(f"{path}: {e}" for e in errs)
                continue

            if doc["scope"] != scope:
                errors.append(f"{path}: scope {doc['scope']!r} does not match directory {scope!r}")

            forwarded = doc["expectation"]["forwarded"]
            if forwarded is not None:
                p_errs = validator.validate(forwarded, payload_schema)
                p_errs.extend(_optional_jsonschema_check(registry, "hook-payload.schema.json", forwarded))
                if p_errs:
                    errors.extend(f"{path} (forwarded): {e}" for e in p_errs)

            fixtures_by_scope[scope][doc["name"]] = doc

    errors.extend(check_cross_os_neutrality(fixtures_by_scope))
    return file_count, errors


def run_self_tests(validator: Draft202012Validator, registry: SchemaRegistry) -> list[str]:
    errors: list[str] = []
    envelope_schema = registry.by_name["hook-envelope.schema.json"]
    payload_schema = registry.by_name["hook-payload.schema.json"]
    fixture_schema = registry.by_name["golden-fixture.schema.json"]

    def expect_valid(label: str, schema_name: str, schema: dict[str, Any], instance: Any) -> None:
        errs = validator.validate(instance, schema)
        errs.extend(_optional_jsonschema_check(registry, schema_name, instance))
        if errs:
            errors.append(f"SELF-TEST PASS FAILED [{label}]: {errs}")

    def expect_invalid(label: str, schema: dict[str, Any], instance: Any) -> None:
        errs = validator.validate(instance, schema)
        if not errs:
            errors.append(f"SELF-TEST NEGATIVE FAILED [{label}]: expected failure, got valid")

    # --- hook-envelope.schema.json positive cases ---
    expect_valid(
        "edge-v1",
        "hook-envelope.schema.json",
        envelope_schema,
        {
            "hook_event_name": "PermissionRequest",
            "session_id": "c1a0de00-0000-4000-8000-000000000001",
            "tool_name": "Bash",
            "tool_input": {"command": "make"},
            "_edge": {
                "v": 1,
                "source": "claude",
                "event": "PermissionRequest",
                "cwd": "/home/dev/project",
                "tty": "/dev/pts/3",
                "stdin_sha256": "9f2c01ab",
                "waits": True,
                "host": {"id": "devbox", "name": "Dev Box"},
                "env": {"TERM_PROGRAM": "ghostty", "TMUX_PANE": "%1"},
                "tmux_client_tty": "/dev/pts/1",
                "ppid": 4242,
            },
        },
    )
    expect_valid(
        "edge-v2-forward-compat",
        "hook-envelope.schema.json",
        envelope_schema,
        {
            "hook_event_name": "Stop",
            "session_id": "s-1",
            "_edge": {"v": 2, "source": "codex", "future_field": {"x": 1}},
        },
    )
    expect_valid(
        "ipc-envelope-v1",
        "hook-envelope.schema.json",
        envelope_schema,
        {
            "v": 1,
            "payload": {
                "hook_event_name": "Stop",
                "session_id": "s-1",
                "_source": "claude",
                "_ppid": 1234,
            },
        },
    )
    expect_valid(
        "windows-protocol-envelope-v1",
        "hook-envelope.schema.json",
        envelope_schema,
        {
            "protocolVersion": 1,
            "event": {
                "eventId": "event-1",
                "sessionId": "session-1",
                "agent": "claude",
                "type": "permission_request",
                "timestamp": "2026-11-16T11:00:00Z",
                "workingDirectory": "C:\\work\\repo",
                "title": None,
                "text": "Allow?",
                "toolName": "Bash",
                "payload": {"command": "ls"},
                "processId": 4321,
                "terminalKind": "wt",
            },
        },
    )

    # --- hook-envelope.schema.json negative cases ---
    expect_invalid(
        "windows-protocol-version-99",
        envelope_schema,
        {
            "protocolVersion": 99,
            "event": {
                "eventId": "event-1",
                "sessionId": "session-1",
                "agent": "claude",
                "type": "session_start",
                "timestamp": "2026-11-16T11:00:00Z",
            },
        },
    )
    expect_invalid(
        "windows-unknown-agent",
        envelope_schema,
        {
            "protocolVersion": 1,
            "event": {
                "eventId": "event-1",
                "sessionId": "session-1",
                "agent": "nonexistent",
                "type": "session_start",
                "timestamp": "2026-11-16T11:00:00Z",
            },
        },
    )
    expect_invalid(
        "ipc-envelope-extra-field",
        envelope_schema,
        {
            "v": 1,
            "payload": {"hook_event_name": "Stop", "session_id": "s-1"},
            "extra": True,
        },
    )
    expect_invalid(
        "ipc-envelope-v2",
        envelope_schema,
        {
            "v": 2,
            "payload": {"hook_event_name": "Stop", "session_id": "s-1"},
        },
    )
    expect_invalid(
        "edge-v0",
        envelope_schema,
        {"_edge": {"v": 0, "source": "claude"}},
    )
    expect_invalid(
        "edge-non-hex-sha",
        envelope_schema,
        {"_edge": {"v": 1, "stdin_sha256": "not-hex!"}},
    )
    expect_invalid("empty-envelope", envelope_schema, {})

    # --- hook-payload.schema.json positive cases ---
    expect_valid(
        "payload-full-fields",
        "hook-payload.schema.json",
        payload_schema,
        {
            "hook_event_name": "PermissionRequest",
            "session_id": "c1a0de00-0000-4000-8000-000000000001",
            "_source": "cursor-cli",
            "_ppid": "$PID0",
            "_hook_ppid": "$PID1",
            "_via_plugin": False,
            "_cursor_payload_digest": "04d112b6484faa502ceacc9a4a59c4fb18ca320f6d8439733f31c5c19c47eb9e",
            "_term_app": "WezTerm",
            "_term_bundle": "com.github.wez.wezterm",
            "_iterm_session": "6A1B2C3D",
            "_kitty_window": "3",
            "_tmux": "/tmp/tmux-501/default,1,0",
            "_tmux_pane": "%7",
            "_tmux_client_tty": "/dev/ttys004",
            "_tty": None,
            "_cmux_surface_id": "surface-1",
            "_cmux_workspace_id": "workspace-1",
            "_zellij": "0",
            "_zellij_pane_id": "5",
            "_zellij_session_name": "main",
            "_wezterm_pane": "12",
            "_herdr_pane_id": "p-1",
            "_herdr_socket_path": "/tmp/herdr.sock",
            "_herdr_bin_path": "/opt/herdr/bin/herdr",
            "_superset_workspace_id": "sw-1",
            "_superset_pane_id": "st-1",
            "_orca_terminal_handle": "orca-1",
            "_orca_worktree_id": "wt-1",
            "_claude_desktop_session": "local_x",
            "_hermes_home": "$HOME/.hermes",
            "_hermes_store": {"title": "Fix it"},
            "_remote_host_id": "devbox",
            "_remote_host_name": "Dev Box",
            "_untracked_process": True,
            "_pi_tool_call_id": "call_1",
            "_env": {"TERM_PROGRAM": "ghostty"},
            "_server_port": 4096,
            "cwd": "/Users/golden/project",
            "transcript_path": "/Users/golden/t.jsonl",
            "tool_name": "Bash",
            "tool_input": {"command": "ls"},
            "tool_use_id": "toolu_01",
            "cursor_version": "3.25.9",
            "conversation_id": "conv-1",
            "question": {"text": "Choose"},
            "options": ["a", "b"],
            "prompt": [{"type": "text", "text": "hello"}],
        },
    )
    expect_valid(
        "payload-numeric-ppid-null-tools",
        "hook-payload.schema.json",
        payload_schema,
        {
            "hook_event_name": "post_llm_call",
            "session_id": "20261009_101151_eafbd0",
            "_ppid": 0,
            "_source": "hermes",
            "tool_name": None,
            "tool_input": None,
            "question": "Pick one",
            "prompt": "hi",
        },
    )

    # --- hook-payload.schema.json negative cases ---
    expect_invalid(
        "payload-missing-session-id",
        payload_schema,
        {"hook_event_name": "Stop", "_source": "claude"},
    )
    expect_invalid(
        "payload-missing-hook-event-name",
        payload_schema,
        {"session_id": "s-1", "_source": "claude"},
    )
    expect_invalid(
        "payload-invalid-cursor-digest",
        payload_schema,
        {
            "hook_event_name": "stop",
            "session_id": "s-1",
            "_cursor_payload_digest": "deadbeef",
        },
    )
    expect_invalid(
        "payload-invalid-ppid-bool",
        payload_schema,
        {"hook_event_name": "Stop", "session_id": "s-1", "_ppid": True},
    )
    expect_invalid(
        "payload-invalid-ppid-negative",
        payload_schema,
        {"hook_event_name": "Stop", "session_id": "s-1", "_ppid": -1},
    )
    expect_invalid(
        "payload-empty-source",
        payload_schema,
        {"hook_event_name": "Stop", "session_id": "s-1", "_source": ""},
    )
    expect_invalid(
        "payload-invalid-via-plugin",
        payload_schema,
        {"hook_event_name": "Stop", "session_id": "s-1", "_via_plugin": "yes"},
    )

    # --- golden-fixture.schema.json + cross-OS neutrality self-tests ---
    sample_input = {
        "arguments": ["--source", "claude"],
        "environment": {},
        "stdin": "{}",
        "ancestors": [{"path": "neutral/proc1", "arguments": []}],
        "bundle_identifiers": {},
        "reply": "{}",
        "files": {},
        "has_socket": True,
    }
    neutral_fixture = {
        "name": "sample",
        "scope": "neutral",
        "input": sample_input,
        "expectation": {
            "forwarded": {"hook_event_name": "Stop", "session_id": "s-1", "_source": "claude"},
            "stdout": "",
            "status": 0,
        },
    }
    macos_fixture = {
        "name": "sample",
        "scope": "macos",
        "input": sample_input,
        "expectation": {
            "forwarded": {
                "hook_event_name": "Stop",
                "session_id": "s-1",
                "_source": "claude",
                "_ppid": "$PID0",
                "_term_bundle": "com.apple.Terminal",
            },
            "stdout": "",
            "status": 0,
        },
    }
    linux_fixture = {
        "name": "sample",
        "scope": "linux",
        "input": sample_input,
        "expectation": {
            "forwarded": {
                "hook_event_name": "Stop",
                "session_id": "s-1",
                "_source": "claude",
                "_ppid": "$PID0",
                "_tty": "/dev/pts/1",
            },
            "stdout": "",
            "status": 0,
        },
    }
    windows_fixture = {
        "name": "sample",
        "scope": "windows",
        "input": sample_input,
        "expectation": {
            "forwarded": {
                "hook_event_name": "Stop",
                "session_id": "s-1",
                "_source": "claude",
                "_ppid": "$PID0",
            },
            "stdout": "",
            "status": 0,
        },
    }
    expect_valid("golden-fixture-neutral", "golden-fixture.schema.json", fixture_schema, neutral_fixture)
    expect_valid(
        "golden-fixture-null-forwarded",
        "golden-fixture.schema.json",
        fixture_schema,
        {
            "name": "empty-stdin",
            "scope": "neutral",
            "input": sample_input,
            "expectation": {"forwarded": None, "stdout": "", "status": 0},
        },
    )
    expect_invalid(
        "golden-fixture-bad-scope",
        fixture_schema,
        {**neutral_fixture, "scope": "freebsd"},
    )

    neutrality_ok = check_cross_os_neutrality({
        "neutral": {"sample": neutral_fixture},
        "macos": {"sample": macos_fixture},
        "linux": {"sample": linux_fixture},
        "windows": {"sample": windows_fixture},
    })
    if neutrality_ok:
        errors.append(f"SELF-TEST NEUTRALITY PASS FAILED: {neutrality_ok}")

    neutrality_bad = check_cross_os_neutrality({
        "neutral": {"sample": neutral_fixture},
        "linux": {
            "sample": {
                **linux_fixture,
                "expectation": {
                    "forwarded": {
                        "hook_event_name": "Stop",
                        "session_id": "s-1",
                        "_source": "claude",
                        "_term_bundle": "com.apple.Terminal",
                    },
                    "stdout": "",
                    "status": 0,
                },
            }
        },
    })
    if not neutrality_bad:
        errors.append("SELF-TEST NEUTRALITY NEGATIVE FAILED: linux with _term_bundle was accepted")

    return errors


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--schemas-dir", type=Path, default=repo_root / "schemas")
    parser.add_argument("--fixtures-dir", type=Path, default=repo_root / "fixtures")
    parser.add_argument("--self-test-only", action="store_true", help="Run built-in schema self-tests only.")
    args = parser.parse_args()

    registry = SchemaRegistry(args.schemas_dir)
    validator = Draft202012Validator(registry)

    self_errors = run_self_tests(validator, registry)
    if self_errors:
        for err in self_errors:
            print(f"ERROR: {err}", file=sys.stderr)
        return 1
    print("Self-tests passed (hook-envelope, hook-payload, golden-fixture, cross-OS neutrality).")

    if args.self_test_only:
        return 0

    if not args.fixtures_dir.exists():
        print(f"Notice: fixtures directory not found at {args.fixtures_dir} (skipping fixture validation).")
        return 0

    file_count, fixture_errors = validate_fixtures_dir(args.fixtures_dir, validator, registry)
    if fixture_errors:
        for err in fixture_errors:
            print(f"ERROR: {err}", file=sys.stderr)
        return 1

    print(f"Validated {file_count} fixture file(s) successfully.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
