//! The Codex hooks feature flag, edited in place
//! (`macos/Sources/MorrowCore/CodexHooksConfig.swift`, #354).
//!
//! Codex only reads `hooks.json` when `config.toml` says `features.hooks =
//! true`. This is deliberately **not** a TOML parser: values stay opaque, and a
//! layout this scanner cannot vouch for returns `None` rather than risk a
//! duplicate key that stops Codex from starting.
//!
//! Two hazards it exists to avoid: a `hooks = true` under `[tui]` is not the
//! feature flag, and an older build of ours appended a `[features]` block even
//! when the table already existed — `enabling_hooks` heals that shape first.

/// The document with the flag set, or `None` when its layout is unsafe.
pub fn enabling_hooks(contents: &str) -> Option<String> {
    Scanner::new(contents).enabling_hooks(true)
}

struct Flag {
    statement: (usize, usize),
    key: (usize, usize),
    value: (usize, usize),
    key_count: usize,
}

/// A layout this scanner will not vouch for: the caller refuses the file rather
/// than risk a duplicate key (`CodexHooksConfig.Invalid`).
struct Refuse;

struct Edit {
    range: (usize, usize),
    replacement: String,
}

type ParsedKey = (Vec<String>, usize, usize);

struct Scanner {
    source: Vec<char>,
    contents: String,
}

impl Scanner {
    fn new(contents: &str) -> Self {
        Self {
            source: contents.chars().collect(),
            contents: contents.to_owned(),
        }
    }

    fn enabling_hooks(&self, healing: bool) -> Option<String> {
        let statements = self.statements()?;
        if healing {
            // A refusal here is a refusal of the file, as the Swift `try` is.
            if let Some(healed) = self.without_appended_features_table(&statements).ok()? {
                return Scanner::new(&healed).enabling_hooks(false);
            }
        }
        let mut scope: Vec<String> = Vec::new();
        let mut current: Option<Flag> = None;
        let mut legacy: Option<Flag> = None;
        let mut features_header: Option<usize> = None;
        let mut first_table: Option<usize> = None;
        let mut root_dotted_features = false;

        for statement in &statements {
            let (lower, upper) = *statement;
            let mut i = self.skip_spaces(lower, upper);
            if i >= upper || [35, 13, 10].contains(&self.code(i)) {
                continue;
            }
            if self.source[i] == '[' {
                let array = i + 1 < upper && self.source[i + 1] == '[';
                let (path, _end, next) = self.key(i + if array { 2 } else { 1 }, upper)?;
                let close = next;
                if close >= upper
                    || self.source[close] != ']'
                    || (array && (close + 1 >= upper || self.source[close + 1] != ']'))
                    || !self.tail(close + if array { 2 } else { 1 }, upper)
                {
                    return None;
                }
                scope = path;
                if scope.len() >= 2 && scope[0] == "features" && scope[1] == "hooks" {
                    return None;
                }
                if array && scope == ["features"] {
                    return None;
                }
                first_table.get_or_insert(lower);
                if scope == ["features"] {
                    if features_header.is_some() {
                        return None;
                    }
                    features_header = Some(upper);
                }
                continue;
            }
            let key_start = i;
            let (path, end, next) = self.key(i, upper)?;
            i = next;
            if i >= upper || self.source[i] != '=' {
                return None;
            }
            i = self.skip_spaces(i + 1, upper);
            if i >= upper || [35, 13, 10].contains(&self.code(i)) {
                return None;
            }
            if scope.is_empty() && path.len() > 1 && path[0] == "features" {
                root_dotted_features = true;
            }
            let absolute: Vec<String> = scope.iter().chain(path.iter()).cloned().collect();
            if absolute == ["features"] {
                return None;
            }
            if absolute.len() > 2 && absolute[0] == "features" && absolute[1] == "hooks" {
                return None;
            }
            let is_current = absolute == ["features", "hooks"];
            let is_legacy = absolute == ["features", "codex_hooks"];
            if !is_current && !is_legacy {
                continue;
            }
            let mut matched = None;
            for value in ["true", "false"] {
                if self.matches(value, i, upper) && self.tail(i + value.chars().count(), upper) {
                    matched = Some(value);
                    break;
                }
            }
            let value = matched?;
            let flag = Flag {
                statement: (lower, upper),
                key: (key_start, end),
                value: (i, i + value.chars().count()),
                key_count: path.len(),
            };
            if is_current {
                if current.is_some() {
                    return None;
                }
                current = Some(flag);
            } else {
                if legacy.is_some() {
                    return None;
                }
                legacy = Some(flag);
            }
        }

        // A root dotted `features.*` key and an explicit `[features]` header
        // together are a duplicate key Codex refuses to load: do not report
        // such a file as enabled.
        if features_header.is_some() && root_dotted_features {
            return None;
        }

        let mut edits: Vec<Edit> = Vec::new();
        if let Some(current) = current {
            edits.push(Edit {
                range: current.value,
                replacement: "true".to_owned(),
            });
            if let Some(legacy) = legacy {
                edits.push(Edit {
                    range: legacy.statement,
                    replacement: String::new(),
                });
            }
        } else if let Some(legacy) = legacy {
            edits.push(Edit {
                range: legacy.key,
                replacement: if legacy.key_count == 1 {
                    "hooks".to_owned()
                } else {
                    "features.hooks".to_owned()
                },
            });
            edits.push(Edit {
                range: legacy.value,
                replacement: "true".to_owned(),
            });
        } else {
            let newline = if self.contents.contains("\r\n") {
                "\r\n"
            } else {
                "\n"
            };
            let position;
            let addition;
            if let Some(header) = features_header {
                position = header;
                // The header's own newline already ends it.
                let lead = if position > 0 && self.source[position - 1] == '\n' {
                    ""
                } else {
                    newline
                };
                addition = format!("{lead}hooks = true{newline}");
            } else if let Some(table) = first_table {
                position = table;
                addition = format!("features.hooks = true{newline}");
            } else {
                position = self.source.len();
                let pending = !self.source.is_empty() && *self.source.last().unwrap() != '\n';
                addition = format!(
                    "{}features.hooks = true{newline}",
                    if pending { newline } else { "" }
                );
            }
            edits.push(Edit {
                range: (position, position),
                replacement: addition,
            });
        }

        edits.sort_by_key(|edit| std::cmp::Reverse(edit.range.0));
        let mut result = self.source.clone();
        for edit in edits {
            result.splice(edit.range.0..edit.range.1, edit.replacement.chars());
        }
        Some(result.into_iter().collect())
    }

    /// CodeIsland 1.0.35 and earlier appended `[features]` + `hooks = true` at
    /// EOF whenever its line regex missed the flag, even when root dotted
    /// `features.*` keys already defined that table: a duplicate key that stops
    /// Codex from starting (#354). Returns the document without that block (and
    /// the blank line before it), or `None` unless the file ends with exactly
    /// that shape on top of an existing features table.
    fn without_appended_features_table(
        &self,
        statements: &[(usize, usize)],
    ) -> Result<Option<String>, Refuse> {
        let mut features_defined = false;
        let mut last_header: Option<usize> = None;
        for (index, statement) in statements.iter().enumerate() {
            let i = self.skip_spaces(statement.0, statement.1);
            if i >= statement.1 || [35, 13, 10].contains(&self.code(i)) {
                continue;
            }
            if self.source[i] == '[' {
                // Every header but the final one may be the earlier definition.
                if let Some(previous) = last_header {
                    if self.is_features_header(statements[previous]) {
                        features_defined = true;
                    }
                }
                last_header = Some(index);
            } else if last_header.is_none() {
                let (path, _end, _next) = self.key(i, statement.1).ok_or(Refuse)?;
                if path.len() > 1 && path[0] == "features" {
                    features_defined = true;
                }
            }
        }
        // Nothing to heal: the flag is simply absent.
        if !features_defined {
            return Ok(None);
        }
        let Some(last_header) = last_header else {
            return Ok(None);
        };
        let header = statements[last_header];
        let open = self.skip_spaces(header.0, header.1);
        if !self.matches("[features]", open, header.1) || !self.is_blank(open + 10, header.1) {
            return Ok(None);
        }
        let mut flags = 0;
        for statement in &statements[(last_header + 1).min(statements.len())..] {
            if self.is_blank(statement.0, statement.1) {
                continue;
            }
            let first = self.skip_spaces(statement.0, statement.1);
            if self.source[first] == '#' {
                return Ok(None);
            }
            let (path, next) = {
                let parsed = self.key(first, statement.1).ok_or(Refuse)?;
                (parsed.0, parsed.2)
            };
            if path != ["hooks"] || next >= statement.1 || self.source[next] != '=' {
                return Ok(None);
            }
            let value = self.skip_spaces(next + 1, statement.1);
            let valid = ["true", "false"].iter().any(|text| {
                self.matches(text, value, statement.1)
                    && self.is_blank(value + text.chars().count(), statement.1)
            });
            if !valid {
                return Ok(None);
            }
            flags += 1;
        }
        if flags != 1 {
            return Ok(None);
        }
        let mut start = header.0;
        if last_header > 0
            && self.is_blank(statements[last_header - 1].0, statements[last_header - 1].1)
        {
            start = statements[last_header - 1].0;
        }
        Ok(Some(self.source[..start].iter().collect()))
    }

    /// `[features]` in any spelling (quoted, spaced, commented); not
    /// `[[features]]`.
    fn is_features_header(&self, statement: (usize, usize)) -> bool {
        let open = self.skip_spaces(statement.0, statement.1);
        if open + 1 >= statement.1 || self.source[open + 1] == '[' {
            return false;
        }
        let Some((path, _end, next)) = self.key(open + 1, statement.1) else {
            return false;
        };
        path == ["features"] && next < statement.1 && self.source[next] == ']'
    }

    fn is_blank(&self, start: usize, end: usize) -> bool {
        self.source[start.min(self.source.len())..end.min(self.source.len())]
            .iter()
            .all(|ch| [32, 9, 13, 10].contains(&(*ch as u32)))
    }

    /// Newlines inside strings or nested array/inline-table values do not start
    /// a new statement. Ranges keep comments and line endings.
    fn statements(&self) -> Option<Vec<(usize, usize)>> {
        let mut ranges: Vec<(usize, usize)> = Vec::new();
        let mut stack: Vec<char> = Vec::new();
        let mut start = 0;
        let mut i = 0;
        while i < self.source.len() {
            let ch = self.source[i];
            if ch == '"' || ch == '\'' {
                i = self.string(i, self.source.len(), true)?.0;
                continue;
            }
            if ch == '#' {
                while i < self.source.len() && self.source[i] != '\n' {
                    i += 1;
                }
                continue;
            }
            if ch == '[' || ch == '{' {
                stack.push(ch);
            } else if ch == ']' || ch == '}' {
                let expected = if ch == ']' { '[' } else { '{' };
                if stack.pop() != Some(expected) {
                    return None;
                }
            } else if ch == '\r' {
                if i + 1 >= self.source.len() || self.source[i + 1] != '\n' {
                    return None;
                }
            } else if self.is_control(ch) {
                return None;
            }
            if ch == '\n' && stack.is_empty() {
                ranges.push((start, i + 1));
                start = i + 1;
            }
            i += 1;
        }
        if !stack.is_empty() {
            return None;
        }
        if start < self.source.len() {
            ranges.push((start, self.source.len()));
        }
        Some(ranges)
    }

    fn key(&self, start: usize, limit: usize) -> Option<ParsedKey> {
        let mut path: Vec<String> = Vec::new();
        let mut i = start;
        loop {
            i = self.skip_spaces(i, limit);
            if i >= limit {
                return None;
            }
            if self.source[i] == '"' || self.source[i] == '\'' {
                let (end, value) = self.string(i, limit, false)?;
                path.push(value);
                i = end;
            } else {
                let begin = i;
                while i < limit && self.is_bare_key(self.source[i]) {
                    i += 1;
                }
                if i == begin {
                    return None;
                }
                path.push(self.source[begin..i].iter().collect());
            }
            let end = i;
            i = self.skip_spaces(i, limit);
            if i == limit || self.source[i] != '.' {
                return Some((path, end, i));
            }
            i += 1;
        }
    }

    fn string(&self, start: usize, limit: usize, multiline: bool) -> Option<(usize, String)> {
        let quote = self.source[start];
        let triple =
            start + 2 < limit && self.source[start + 1] == quote && self.source[start + 2] == quote;
        if triple && !multiline {
            return None;
        }
        let mut i = start + if triple { 3 } else { 1 };
        let mut out: Vec<char> = Vec::new();
        while i < limit {
            let ch = self.source[i];
            if ch == quote {
                let mut end = i + 1;
                if triple {
                    while end < limit && self.source[end] == quote {
                        end += 1;
                    }
                    let count = end - i;
                    if count < 3 {
                        out.extend(std::iter::repeat_n(quote, count));
                        i = end;
                        continue;
                    }
                    if count > 5 {
                        return None;
                    }
                    out.extend(std::iter::repeat_n(quote, count - 3));
                }
                return Some((end, out.into_iter().collect()));
            }
            if ch == '\\' && quote == '"' {
                i += 1;
                if i >= limit {
                    return None;
                }
                let escaped = self.source[i];
                if triple && [32, 9, 13, 10].contains(&(escaped as u32)) {
                    let mut saw_newline = false;
                    while i < limit && [32, 9, 13, 10].contains(&(self.source[i] as u32)) {
                        if self.source[i] == '\r' && (i + 1 >= limit || self.source[i + 1] != '\n')
                        {
                            return None;
                        }
                        saw_newline = saw_newline || self.source[i] == '\n';
                        i += 1;
                    }
                    if !saw_newline {
                        return None;
                    }
                    continue;
                }
                let simple = match escaped {
                    'b' => Some('\u{8}'),
                    't' => Some('\t'),
                    'n' => Some('\n'),
                    'f' => Some('\u{C}'),
                    'r' => Some('\r'),
                    '"' => Some('"'),
                    '\\' => Some('\\'),
                    _ => None,
                };
                if let Some(value) = simple {
                    out.push(value);
                    i += 1;
                    continue;
                }
                if escaped == 'u' || escaped == 'U' {
                    let end = i + if escaped == 'u' { 5 } else { 9 };
                    if end > limit {
                        return None;
                    }
                    let digits: String = self.source[i + 1..end].iter().collect();
                    if !digits.chars().all(|ch| ch.is_ascii_hexdigit()) {
                        return None;
                    }
                    let value = u32::from_str_radix(&digits, 16).ok()?;
                    out.push(char::from_u32(value)?);
                    i = end;
                    continue;
                }
                return None;
            }
            if !triple && (ch == '\r' || ch == '\n') {
                return None;
            }
            if self.is_control(ch) {
                return None;
            }
            if ch == '\r' && (i + 1 >= limit || self.source[i + 1] != '\n') {
                return None;
            }
            out.push(ch);
            i += 1;
        }
        None
    }

    fn skip_spaces(&self, start: usize, limit: usize) -> usize {
        let mut i = start;
        while i < limit && (self.source[i] == ' ' || self.source[i] == '\t') {
            i += 1;
        }
        i
    }

    fn tail(&self, start: usize, limit: usize) -> bool {
        let mut i = start;
        while i < limit && [32, 9, 13, 10].contains(&(self.source[i] as u32)) {
            i += 1;
        }
        i == limit || self.source[i] == '#'
    }

    fn matches(&self, text: &str, start: usize, limit: usize) -> bool {
        let scalars: Vec<char> = text.chars().collect();
        start + scalars.len() <= limit && self.source[start..start + scalars.len()] == scalars[..]
    }

    fn is_bare_key(&self, ch: char) -> bool {
        ch.is_ascii_alphanumeric() || ch == '_' || ch == '-'
    }

    fn is_control(&self, ch: char) -> bool {
        let code = ch as u32;
        (code < 32 && ![9, 13, 10].contains(&code)) || code == 127
    }

    fn code(&self, index: usize) -> u32 {
        self.source[index] as u32
    }
}
