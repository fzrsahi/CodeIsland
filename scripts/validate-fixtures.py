#!/usr/bin/env python3
"""Validate Morrow golden fixture bundles against schemas/ (JSON Schema Draft 2020-12).

Besides the schema, checks what a schema cannot express:
  - neutrality: no expectation in a scope contains a key from that bundle's
    `omitted_keys`, or a value listed for that key in `omitted_values`;
  - every fixture name in a per-OS bundle exists in neutral/.

Requires `jsonschema>=4.18` (pip install -r scripts/requirements-fixtures.txt).
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

try:
    from jsonschema import Draft202012Validator
    from referencing import Registry, Resource
except ImportError:
    sys.exit("ERROR: jsonschema>=4.18 is not installed; run: pip install -r scripts/requirements-fixtures.txt")

SCOPES = ("neutral", "macos", "linux", "windows")
BUNDLE = "bridge-golden.json"


def neutrality_errors(bundle: dict) -> list[str]:
    scope = bundle["scope"]
    keys = set(bundle["omitted_keys"])
    values = bundle["omitted_values"]
    errors = []
    for fixture in bundle["fixtures"]:
        forwarded = fixture["expectation"]["forwarded"] or {}
        for key in sorted(keys & forwarded.keys()):
            errors.append(f"{scope}/{fixture['name']}: omitted key {key} present")
        for key, dropped in values.items():
            if forwarded.get(key) in dropped:
                errors.append(f"{scope}/{fixture['name']}: omitted value {key}={forwarded[key]!r} present")
    return errors


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--schemas-dir", type=Path, default=root / "schemas")
    parser.add_argument("--fixtures-dir", type=Path, default=root / "fixtures")
    args = parser.parse_args()

    schemas = {p.name: json.loads(p.read_text()) for p in sorted(args.schemas_dir.glob("*.schema.json"))}
    registry = Registry().with_resources(
        (schema["$id"], Resource.from_contents(schema)) for schema in schemas.values()
    )
    for schema in schemas.values():
        Draft202012Validator.check_schema(schema)
    validator = Draft202012Validator(schemas["golden-fixture.schema.json"], registry=registry)

    errors: list[str] = []
    names: dict[str, list[str]] = {}
    for scope in SCOPES:
        path = args.fixtures_dir / scope / BUNDLE
        bundle = json.loads(path.read_text())
        schema_errors = [
            f"{scope}/{BUNDLE} at /{'/'.join(map(str, e.absolute_path))}: {e.message}"
            for e in validator.iter_errors(bundle)
        ]
        errors += schema_errors
        if schema_errors:
            continue
        if bundle["scope"] != scope:
            errors.append(f"{path}: scope is {bundle['scope']!r}, expected {scope!r}")
        errors += neutrality_errors(bundle)
        names[scope] = [f["name"] for f in bundle["fixtures"]]
        print(f"{scope}/{BUNDLE}: {len(names[scope])} fixtures, omits {len(bundle['omitted_keys'])} keys")

    neutral = set(names.get("neutral", []))
    for scope in SCOPES[1:]:
        for name in names.get(scope, []):
            if name not in neutral:
                errors.append(f"{scope}/{BUNDLE}: fixture {name!r} not in neutral/{BUNDLE}")

    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    if errors:
        return 1
    print(f"All {len(SCOPES)} bundles valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
