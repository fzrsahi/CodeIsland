#!/usr/bin/env python3
"""Validate fixtures/endpoint/cases.json against schemas/endpoint-cases.schema.json.

Also checks what the schema cannot say: case names are unique and start with
the case's os. Exit 0 when valid, 1 otherwise.

    python3 -m pip install -r shared/contract/requirements-endpoint-cases.txt
    python3 scripts/validate-endpoint-cases.py
"""
import json
import pathlib
import sys

from jsonschema import Draft202012Validator

ROOT = pathlib.Path(__file__).resolve().parent
SCHEMA = ROOT / "schemas" / "endpoint-cases.schema.json"
CASES = ROOT / "fixtures" / "endpoint" / "cases.json"


def main() -> int:
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(schema)
    data = json.loads(CASES.read_text(encoding="utf-8"))
    errors = [
        f"{'/'.join(map(str, e.absolute_path)) or '<root>'}: {e.message}"
        for e in Draft202012Validator(schema).iter_errors(data)
    ]
    seen = set()
    for case in data.get("cases", []):
        name = case.get("name")
        if name in seen:
            errors.append(f"duplicate case name: {name}")
        seen.add(name)
        if name and case.get("os") and not name.startswith(case["os"] + "-"):
            errors.append(f"{name}: name must start with its os ({case['os']}-)")
    for error in errors:
        print(f"error: {error}", file=sys.stderr)
    if errors:
        return 1
    counts = {}
    for case in data["cases"]:
        counts[case["os"]] = counts.get(case["os"], 0) + 1
    summary = ", ".join(f"{os} {n}" for os, n in sorted(counts.items()))
    print(f"ok: {len(data['cases'])} cases ({summary})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
