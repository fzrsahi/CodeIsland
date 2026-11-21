//! `CodexTomlHooksFixtures` (`macos/Tests/MorrowTests/CodexTomlHooksFixtures.swift`)
//! ported case for case, plus the idempotence the Swift loop checks: a second
//! pass over its own output changes nothing.

use morrow_core::installer::codex_config::enabling_hooks;

/// `(name, original, expected)`; `None` means the document must be refused.
const CASES: &[(&str, &str, Option<&str>)] = &[
    ("empty", "", Some("features.hooks = true\n")),
    (
        "issue354",
        "\"features\".\"hooks\" = true\nmodel = \"gpt-6-sol\"\n\n[features.context_management]\nexperimental_mode = true\n",
        Some(
            "\"features\".\"hooks\" = true\nmodel = \"gpt-6-sol\"\n\n[features.context_management]\nexperimental_mode = true\n",
        ),
    ),
    (
        "dotted false",
        "  features . 'hooks' = false  # keep\n",
        Some("  features . 'hooks' = true  # keep\n"),
    ),
    (
        "escaped dotted keys",
        "\"\\u0066eatures\".\"\\U00000068ooks\" = false\n",
        Some("\"\\u0066eatures\".\"\\U00000068ooks\" = true\n"),
    ),
    (
        "quoted bare false",
        "[\"features\"]\n\"hooks\" = false # disabled\n",
        Some("[\"features\"]\n\"hooks\" = true # disabled\n"),
    ),
    (
        "literal bare true",
        "['features']\n'hooks' = true\n",
        Some("['features']\n'hooks' = true\n"),
    ),
    (
        "escaped bare key",
        "[features]\n\"\\u0068ooks\" = false\n",
        Some("[features]\n\"\\u0068ooks\" = true\n"),
    ),
    (
        "quoted header",
        "[ \"features\" ] # keep\nother = true\n",
        Some("[ \"features\" ] # keep\nhooks = true\nother = true\n"),
    ),
    (
        "header at EOF",
        "[features]",
        Some("[features]\nhooks = true\n"),
    ),
    (
        "root keys only",
        "model = \"example\"\n",
        Some("model = \"example\"\nfeatures.hooks = true\n"),
    ),
    (
        "commented table",
        "[tui] # UI options\nmax_input_chars = 10\n",
        Some("features.hooks = true\n[tui] # UI options\nmax_input_chars = 10\n"),
    ),
    (
        "commented subtable",
        "[features.context_management] # keep\nexperimental_mode = true\n",
        Some(
            "features.hooks = true\n[features.context_management] # keep\nexperimental_mode = true\n",
        ),
    ),
    (
        "quoted hash in header",
        "[\"tui#view\"] # keep\nvalue = 1\n",
        Some("features.hooks = true\n[\"tui#view\"] # keep\nvalue = 1\n"),
    ),
    (
        "profile flag is not root",
        "[profiles.work]\nfeatures.hooks = false\n",
        Some("features.hooks = true\n[profiles.work]\nfeatures.hooks = false\n"),
    ),
    (
        "unrelated bare flag first",
        "[tui]\nhooks = false\n[features]\nhooks = false\n",
        Some("[tui]\nhooks = false\n[features]\nhooks = true\n"),
    ),
    (
        "root bare hooks is not feature",
        "hooks = true\n",
        Some("hooks = true\nfeatures.hooks = true\n"),
    ),
    (
        "array table",
        "[[agents]] # keep\nhooks = false\n",
        Some("features.hooks = true\n[[agents]] # keep\nhooks = false\n"),
    ),
    (
        "multiline array",
        "values = [\n  \"[features]\",\n  \"features.hooks = false\", # keep\n]\n[tui]\nvalue = 1\n",
        Some(
            "values = [\n  \"[features]\",\n  \"features.hooks = false\", # keep\n]\nfeatures.hooks = true\n[tui]\nvalue = 1\n",
        ),
    ),
    (
        "unrelated inline table",
        "other = { text = \"[features] # not a table\", hooks = false }\n",
        Some(
            "other = { text = \"[features] # not a table\", hooks = false }\nfeatures.hooks = true\n",
        ),
    ),
    (
        "basic multiline string",
        "developer_instructions = \"\"\"\nfeatures.hooks = false\n[features]\n\"\"\"\n[tui]\nvalue = 1\n",
        Some(
            "developer_instructions = \"\"\"\nfeatures.hooks = false\n[features]\n\"\"\"\nfeatures.hooks = true\n[tui]\nvalue = 1\n",
        ),
    ),
    (
        "literal multiline string",
        "developer_instructions = '''\nfeatures.hooks = false\n[features]\n'''\n",
        Some(
            "developer_instructions = '''\nfeatures.hooks = false\n[features]\n'''\nfeatures.hooks = true\n",
        ),
    ),
    (
        "four closing quotes",
        "developer_instructions = \"\"\"text\"\"\"\"\n[tui]\n",
        Some("developer_instructions = \"\"\"text\"\"\"\"\nfeatures.hooks = true\n[tui]\n"),
    ),
    (
        "five closing quotes",
        "developer_instructions = '''text'''''\n[tui]\n",
        Some("developer_instructions = '''text'''''\nfeatures.hooks = true\n[tui]\n"),
    ),
    (
        "CRLF",
        "[features] # keep\r\n\"hooks\" = false # keep\r\n",
        Some("[features] # keep\r\n\"hooks\" = true # keep\r\n"),
    ),
    (
        "comment is not a flag",
        "# features.hooks = false\n# [features]\n",
        Some("# features.hooks = false\n# [features]\nfeatures.hooks = true\n"),
    ),
    (
        "legacy table key",
        "[features]\n'codex_hooks' = false # keep\n",
        Some("[features]\nhooks = true # keep\n"),
    ),
    (
        "legacy dotted key",
        "\"features\".\"codex_hooks\" = true # keep\n",
        Some("features.hooks = true # keep\n"),
    ),
    (
        "remove scoped legacy only",
        "[tui]\ncodex_hooks = false\n[features]\nhooks = true\ncodex_hooks = true\n",
        Some("[tui]\ncodex_hooks = false\n[features]\nhooks = true\n"),
    ),
    (
        "remove dotted legacy",
        "features.hooks = false\nfeatures.codex_hooks = true\n",
        Some("features.hooks = true\n"),
    ),
    (
        "heal pre-fix block after dotted flag",
        "\"features\".\"hooks\" = true\nmodel = \"gpt-6-sol\"\n\n[features.context_management]\nexperimental_mode = true\n\n[features]\nhooks = true",
        Some(
            "\"features\".\"hooks\" = true\nmodel = \"gpt-6-sol\"\n\n[features.context_management]\nexperimental_mode = true\n",
        ),
    ),
    (
        "heal pre-fix block after dotted feature",
        "features.other = true\n\n[tui]\nx = 1\n\n[features]\nhooks = true\n",
        Some("features.other = true\n\nfeatures.hooks = true\n[tui]\nx = 1\n"),
    ),
    (
        "heal pre-fix block after commented header",
        "[features] # flags\r\nother = true\r\n\n[features]\nhooks = true\n",
        Some("[features] # flags\r\nhooks = true\r\nother = true\r\n"),
    ),
    (
        "dotted feature plus table is unsafe",
        "features.other = true\n[features]\nhooks = true\nmodel = \"x\"\n",
        None,
    ),
    (
        "edited pre-fix block is not healed",
        "features.other = true\n\n[features]\n# mine\nhooks = true\n",
        None,
    ),
    (
        "inline features is unsafe",
        "features = { hooks = false }\n",
        None,
    ),
    (
        "nonboolean hooks is unsafe",
        "[features]\nhooks = \"false\"\n",
        None,
    ),
    (
        "hooks subtable is unsafe",
        "[features.hooks]\nvalue = true\n",
        None,
    ),
    (
        "features array is unsafe",
        "[[features]]\nhooks = false\n",
        None,
    ),
    (
        "duplicate hooks is unsafe",
        "features.hooks = true\nfeatures.hooks = false\n",
        None,
    ),
    (
        "unclosed string is unsafe",
        "developer_instructions = \"\"\"\nfeatures.hooks = false\n",
        None,
    ),
];

#[test]
fn every_fixture_case_matches_swift() {
    let mut mismatches: Vec<String> = Vec::new();
    for (name, original, expected) in CASES {
        let got = enabling_hooks(original);
        match (expected, &got) {
            (Some(expected), Some(got)) => {
                if got != expected {
                    mismatches.push(format!("{name}:\n  want {expected:?}\n  got  {got:?}"));
                    continue;
                }
                // Idempotent: a second pass over its own output is a no-op.
                let again = enabling_hooks(got);
                if again.as_deref() != Some(got.as_str()) {
                    mismatches.push(format!("{name}: not idempotent: {again:?}"));
                }
            }
            (None, None) => {}
            (Some(_), None) => mismatches.push(format!("{name}: refused, Swift accepts")),
            (None, Some(got)) => mismatches.push(format!("{name}: wrote {got:?}, Swift refuses")),
        }
    }
    assert!(mismatches.is_empty(), "\n{}", mismatches.join("\n"));
}

#[test]
fn the_case_count_is_pinned() {
    assert_eq!(CASES.len(), 40, "a fixture was added or dropped");
}
