//! A minimal-diff editor for JSON / JSONC config files
//! (`Sources/Morrow/JSONMinimalEditor.swift`).
//!
//! `serde_json` round-tripping rewrites a whole document: comments go, key
//! order changes, a trailing newline disappears. A user's `settings.json` is
//! theirs, so the installer only replaces the text range of the top-level key
//! it came for and leaves every other byte alone (#89).
//!
//! Works on `char`s, like Swift's `[Character]`. Every index the editor slices
//! at sits between ASCII structural characters, so the two agree byte for byte.

use serde_json::Value;

/// Set (insert or replace) the value of `key` at the top level of `source`.
///
/// `None` when `source` is not a JSON *object* at the top level, or when it
/// does not parse: the caller must never write the file in that case (#89).
pub fn set_top_level_value(source: &str, key: &str, value: &Value) -> Option<String> {
    let chars: Vec<char> = source.chars().collect();
    let doc = parse_top_level_object(&chars)?;

    let indent = detect_key_indent(&chars, &doc);
    let serialized = serialize_value(value, &indent)?;

    if let Some(entry) = doc.entries.iter().find(|entry| entry.key == key) {
        // Replace the value's text range only.
        let prefix: String = chars[..entry.value_start].iter().collect();
        let suffix: String = chars[entry.value_end..].iter().collect();
        return Some(prefix + &serialized + &suffix);
    }
    insert_key(&chars, &doc, key, &serialized, &indent)
}

/// Delete a top-level `key` from `source`, returning `source` unchanged when
/// the key is absent. `None` when the document is not a JSON object.
pub fn delete_top_level_key(source: &str, key: &str) -> Option<String> {
    let chars: Vec<char> = source.chars().collect();
    let doc = parse_top_level_object(&chars)?;
    let Some(index) = doc.entries.iter().position(|entry| entry.key == key) else {
        return Some(source.to_owned());
    };
    let entry = &doc.entries[index];

    // The removal range, including the adjoining comma.
    let mut remove_start = entry.key_start;
    let mut remove_end = entry.value_end;

    if doc.entries.len() == 1 {
        // Only entry — clear what is between `{` and `}`, leaving an empty object.
        remove_start = doc.object_content_start;
        remove_end = doc.object_content_end;
    } else if index < doc.entries.len() - 1 {
        // Not the last entry — take the trailing comma, then the spaces up to
        // the next entry's own indent and its newline.
        let next_start = doc.entries[index + 1].key_start;
        if let Some(comma) = find_next_nonspace(&chars, entry.value_end, next_start) {
            if chars[comma] == ',' {
                remove_end = comma + 1;
                while remove_end < next_start
                    && (chars[remove_end] == ' ' || chars[remove_end] == '\t')
                {
                    remove_end += 1;
                }
                if remove_end < next_start && chars[remove_end] == '\n' {
                    remove_end += 1;
                }
            }
        }
    } else {
        // Last entry — strip the preceding comma from the entry before it.
        let previous = &doc.entries[index - 1];
        if let Some(comma) = find_prev_nonspace(&chars, entry.key_start, previous.value_end) {
            if chars[comma] == ',' {
                remove_start = comma;
            }
        }
    }

    let prefix: String = chars[..remove_start].iter().collect();
    let suffix: String = chars[remove_end..].iter().collect();
    Some(prefix + &suffix)
}

// MARK: - JSONC

/// Strip `//` and `/* */` comments, leaving strings — a `//` inside a value is
/// data, not a comment (`ConfigInstaller.stripJSONComments`).
///
/// `serde_json` rejects comments, and Claude Code's `settings.json` is JSONC.
/// This is the text a parse sees; the editor itself keeps every byte of the
/// original.
pub fn strip_json_comments(input: &str) -> String {
    let chars: Vec<char> = input.chars().collect();
    let mut out = String::with_capacity(input.len());
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if c == '"' {
            out.push(c);
            i += 1;
            while i < chars.len() {
                let inner = chars[i];
                out.push(inner);
                if inner == '\\' {
                    i += 1;
                    if i < chars.len() {
                        out.push(chars[i]);
                    }
                } else if inner == '"' {
                    break;
                }
                i += 1;
            }
            i += 1;
            continue;
        }
        if c == '/' && i + 1 < chars.len() {
            let next = chars[i + 1];
            if next == '/' {
                i += 2;
                while i < chars.len() && chars[i] != '\n' {
                    i += 1;
                }
                continue;
            }
            if next == '*' {
                i += 2;
                while i < chars.len() {
                    if chars[i] == '*' && i + 1 < chars.len() && chars[i + 1] == '/' {
                        i += 2;
                        break;
                    }
                    i += 1;
                }
                continue;
            }
        }
        out.push(c);
        i += 1;
    }
    out
}

// MARK: - Document model

struct Entry {
    key: String,
    /// Index of the opening `"` of the key literal.
    key_start: usize,
    /// Index of the first character of the value (after `:` and whitespace).
    value_start: usize,
    /// Exclusive.
    value_end: usize,
}

struct Document {
    /// Index just after the opening `{`.
    object_content_start: usize,
    /// Index of the matching `}`.
    object_content_end: usize,
    entries: Vec<Entry>,
}

// MARK: - Parser

fn parse_top_level_object(chars: &[char]) -> Option<Document> {
    let mut i = 0;
    skip_space(chars, &mut i);
    if i >= chars.len() || chars[i] != '{' {
        return None;
    }
    let open_brace = i;
    i += 1;

    let mut entries: Vec<Entry> = Vec::new();
    let mut expect_entry = true;

    loop {
        skip_space(chars, &mut i);
        if i >= chars.len() {
            return None;
        }
        if chars[i] == '}' {
            return Some(Document {
                object_content_start: open_brace + 1,
                object_content_end: i,
                entries,
            });
        }
        if !expect_entry {
            return None; // A missing comma.
        }

        // The key.
        if i >= chars.len() || chars[i] != '"' {
            return None;
        }
        let key_start = i;
        let key = read_string_literal(chars, &mut i)?;

        skip_space(chars, &mut i);
        if i >= chars.len() || chars[i] != ':' {
            return None;
        }
        i += 1;
        skip_space(chars, &mut i);

        let value_start = i;
        if !skip_value(chars, &mut i) {
            return None;
        }
        let value_end = i;

        entries.push(Entry {
            key,
            key_start,
            value_start,
            value_end,
        });

        skip_space(chars, &mut i);
        if i < chars.len() && chars[i] == ',' {
            i += 1;
            expect_entry = true;
            continue;
        }
        expect_entry = false;
    }
}

// MARK: - Scanning primitives

fn skip_space(chars: &[char], i: &mut usize) {
    while *i < chars.len() {
        let c = chars[*i];
        if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
            *i += 1;
            continue;
        }
        if c == '/' && *i + 1 < chars.len() && chars[*i + 1] == '/' {
            *i += 2;
            while *i < chars.len() && chars[*i] != '\n' {
                *i += 1;
            }
            continue;
        }
        if c == '/' && *i + 1 < chars.len() && chars[*i + 1] == '*' {
            *i += 2;
            while *i + 1 < chars.len() {
                if chars[*i] == '*' && chars[*i + 1] == '/' {
                    *i += 2;
                    break;
                }
                *i += 1;
            }
            continue;
        }
        break;
    }
}

/// Reads a JSON string literal starting at `i` and advances past its closing `"`.
fn read_string_literal(chars: &[char], i: &mut usize) -> Option<String> {
    if *i >= chars.len() || chars[*i] != '"' {
        return None;
    }
    *i += 1;
    let mut out = String::new();
    while *i < chars.len() {
        let c = chars[*i];
        if c == '\\' {
            if *i + 1 >= chars.len() {
                return None;
            }
            let escaped = chars[*i + 1];
            match escaped {
                '"' => out.push('"'),
                '\\' => out.push('\\'),
                '/' => out.push('/'),
                'b' => out.push('\u{08}'),
                'f' => out.push('\u{0C}'),
                'n' => out.push('\n'),
                'r' => out.push('\r'),
                't' => out.push('\t'),
                'u' => {
                    if *i + 5 >= chars.len() {
                        return None;
                    }
                    let hex: String = chars[*i + 2..=*i + 5].iter().collect();
                    let code = u32::from_str_radix(&hex, 16).ok()?;
                    out.push(char::from_u32(code)?);
                    *i += 6;
                    continue;
                }
                other => out.push(other),
            }
            *i += 2;
            continue;
        }
        if c == '"' {
            *i += 1;
            return Some(out);
        }
        out.push(c);
        *i += 1;
    }
    None
}

/// Advances `i` past a JSON value without parsing it.
fn skip_value(chars: &[char], i: &mut usize) -> bool {
    skip_space(chars, i);
    if *i >= chars.len() {
        return false;
    }
    match chars[*i] {
        '"' => read_string_literal(chars, i).is_some(),
        '{' => skip_object_or_array(chars, i, '{', '}'),
        '[' => skip_object_or_array(chars, i, '[', ']'),
        't' | 'f' | 'n' => {
            while *i < chars.len() && chars[*i].is_alphabetic() {
                *i += 1;
            }
            true
        }
        c if c == '-' || c == '+' || c.is_ascii_digit() => {
            while *i < chars.len() {
                let cc = chars[*i];
                if cc.is_ascii_digit()
                    || cc == '.'
                    || cc == 'e'
                    || cc == 'E'
                    || cc == '-'
                    || cc == '+'
                {
                    *i += 1;
                } else {
                    break;
                }
            }
            true
        }
        _ => false,
    }
}

fn skip_object_or_array(chars: &[char], i: &mut usize, open: char, close: char) -> bool {
    if *i >= chars.len() || chars[*i] != open {
        return false;
    }
    *i += 1;
    let mut depth = 1;
    while *i < chars.len() && depth > 0 {
        let c = chars[*i];
        if c == '"' {
            if read_string_literal(chars, i).is_none() {
                return false;
            }
            continue;
        }
        if c == '/' && *i + 1 < chars.len() && (chars[*i + 1] == '/' || chars[*i + 1] == '*') {
            skip_space(chars, i);
            continue;
        }
        if c == open || c == '{' || c == '[' {
            depth += 1;
        } else if c == close || c == '}' || c == ']' {
            // Generic `{`/`[` to `}`/`]` matching is sloppy for mixed nesting,
            // but JSON nesting is well formed: each opener pairs with its own
            // closer.
            depth -= 1;
            if depth == 0 {
                *i += 1;
                return true;
            }
        }
        *i += 1;
    }
    depth == 0
}

fn find_next_nonspace(chars: &[char], from: usize, stop_at: usize) -> Option<usize> {
    let mut i = from;
    while i < stop_at {
        let c = chars[i];
        if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
            i += 1;
            continue;
        }
        if c == '/' && i + 1 < stop_at && chars[i + 1] == '/' {
            i += 2;
            while i < stop_at && chars[i] != '\n' {
                i += 1;
            }
            continue;
        }
        if c == '/' && i + 1 < stop_at && chars[i + 1] == '*' {
            i += 2;
            while i + 1 < stop_at {
                if chars[i] == '*' && chars[i + 1] == '/' {
                    i += 2;
                    break;
                }
                i += 1;
            }
            continue;
        }
        return Some(i);
    }
    None
}

fn find_prev_nonspace(chars: &[char], from: usize, stop_at: usize) -> Option<usize> {
    if from == 0 {
        return None;
    }
    let mut i = from - 1;
    loop {
        if i < stop_at {
            return None;
        }
        let c = chars[i];
        if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
            if i == 0 {
                return None;
            }
            i -= 1;
            continue;
        }
        return Some(i);
    }
}

// MARK: - Indent detection

/// What sits between the previous newline (or the start of the text) and
/// `index`, when it is only spaces and tabs. An entry that shares its line with
/// the `{` yields `Some("")`.
fn line_prefix(chars: &[char], index: usize) -> Option<String> {
    let mut start = index;
    while start > 0 && chars[start - 1] != '\n' {
        start -= 1;
    }
    let prefix: String = chars[start..index].iter().collect();
    prefix
        .chars()
        .all(|c| c == ' ' || c == '\t')
        .then_some(prefix)
}

fn detect_key_indent(chars: &[char], doc: &Document) -> String {
    // Prefer the indent of the first entry.
    if let Some(first) = doc.entries.first() {
        if let Some(prefix) = line_prefix(chars, first.key_start) {
            return prefix;
        }
    }
    // Fallback: the closing `}`'s indent plus two spaces.
    match line_prefix(chars, doc.object_content_end) {
        Some(prefix) => prefix + "  ",
        None => "  ".to_owned(),
    }
}

fn closing_brace_indent(chars: &[char], doc: &Document) -> String {
    line_prefix(chars, doc.object_content_end).unwrap_or_default()
}

// MARK: - Insertion

fn insert_key(
    chars: &[char],
    doc: &Document,
    key: &str,
    serialized: &str,
    key_indent: &str,
) -> Option<String> {
    let closing_indent = closing_brace_indent(chars, doc);
    let entry = format!("\"{}\": {}", escape(key), serialized);

    if doc.entries.is_empty() {
        // `{}` or `{   }` — the content becomes a single entry.
        let prefix: String = chars[..doc.object_content_start].iter().collect();
        let suffix: String = chars[doc.object_content_end..].iter().collect();
        return Some(format!(
            "{prefix}\n{key_indent}{entry}\n{closing_indent}{suffix}"
        ));
    }

    // Append after the last entry's value, before the closing `}`, keeping the
    // whitespace between them.
    let last = doc.entries.last()?;
    let prefix: String = chars[..last.value_end].iter().collect();
    let suffix: String = chars[last.value_end..].iter().collect();
    let tail = &chars[last.value_end..doc.object_content_end];
    let has_newline = tail.contains(&'\n');
    let inserted = if has_newline {
        format!(",\n{key_indent}{entry}")
    } else {
        format!(",\n{key_indent}{entry}\n{closing_indent}")
    };
    Some(prefix + &inserted + &suffix)
}

fn escape(source: &str) -> String {
    let mut out = String::new();
    for c in source.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{08}' => out.push_str("\\b"),
            '\u{0C}' => out.push_str("\\f"),
            other => out.push(other),
        }
    }
    out
}

// MARK: - Value serialization

/// A value as JSON text ready to sit after `"key": `, its nested lines carrying
/// the containing key's indent.
///
/// `serde_json`'s pretty printer indents by two spaces per level, which is what
/// `JSONSerialization` does; the difference between them is the space before a
/// colon, and no caller compares our output with Swift's.
pub fn serialize_value(value: &Value, key_indent: &str) -> Option<String> {
    let raw = serde_json::to_string_pretty(value).ok()?;
    Some(reindent(&raw, key_indent))
}

/// Prepend `key_indent` to every line but the first, so the value lines up
/// inside its parent object.
fn reindent(raw: &str, key_indent: &str) -> String {
    let mut lines: Vec<&str> = raw.split('\n').collect();
    if lines.len() <= 1 {
        return raw.to_owned();
    }
    let mut out = String::from(lines[0]);
    for line in lines.drain(1..) {
        out.push('\n');
        if !line.is_empty() {
            out.push_str(key_indent);
            out.push_str(line);
        }
    }
    out
}
