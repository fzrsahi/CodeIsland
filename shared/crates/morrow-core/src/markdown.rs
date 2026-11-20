//! The block structure of an assistant reply (`MarkdownBlockParser`,
//! `Sources/MorrowCore/MarkdownBlockParser.swift`): ATX/setext headings,
//! paragraphs, bullet/ordered/task lists with nesting, fenced code, GFM
//! tables, block quotes and thematic breaks.
//!
//! Inline spans (bold, code, links, …) stay as raw Markdown source inside a
//! block: the renderer parses them separately, so this layer never
//! re-implements emphasis rules and the inline layer never sees list markers
//! or table pipes. The frontend draws the blocks; nothing here writes HTML.
//!
//! It follows CommonMark/GFM where replies depend on it and is deliberately
//! lenient where models are sloppy (two-space nesting under "1.", a delimiter
//! row with the wrong cell count). Replies are parsed while they stream in,
//! so every construct tolerates being cut off midway: an unclosed fence is
//! still a code block, a half-written delimiter row is still a table, and no
//! input is dropped.
//!
//! Unicode: Swift counts and splits `Character`s (grapheme clusters); this
//! counts and splits `char`s (scalar values).

/// Lists and quotes nest at most this deep; anything below is kept as plain
/// paragraph text so pathological input cannot build a view tree (or a
/// recursion) of unbounded depth.
pub const MAX_NESTING_DEPTH: usize = 6;

/// The widest table the parser builds; cells past it join the last column.
pub const MAX_TABLE_COLUMNS: usize = 16;

// MARK: - Model

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum MarkdownBlock {
    Heading {
        level: usize,
        text: String,
    },
    /// Lines of one paragraph, joined with "\n". Newlines are kept rather
    /// than folded into spaces — replies use them intentionally.
    Paragraph(String),
    List(MarkdownList),
    Code(MarkdownCodeBlock),
    Table(MarkdownTable),
    Quote(Vec<MarkdownBlock>),
    ThematicBreak,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MarkdownList {
    pub is_ordered: bool,
    /// Number of the first item; later items count up from it, as in
    /// CommonMark (so "1. 1. 1." still renders as 1, 2, 3).
    pub start: i64,
    pub items: Vec<MarkdownListItem>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MarkdownListItem {
    /// Set for GFM task items (`- [ ]` / `- [x]`).
    pub checkbox: Option<Checkbox>,
    /// The item's content: usually one paragraph, plus nested lists, code, …
    pub blocks: Vec<MarkdownBlock>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Checkbox {
    Unchecked,
    Checked,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MarkdownCodeBlock {
    /// First word of the fence's info string (` ```swift ` → "swift").
    pub language: Option<String>,
    pub code: String,
    /// False while a streaming reply has opened the fence but not closed it.
    pub is_closed: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MarkdownTableAlignment {
    Automatic,
    Leading,
    Center,
    Trailing,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MarkdownTable {
    pub header: Vec<String>,
    pub alignments: Vec<MarkdownTableAlignment>,
    /// Body rows. Header, alignments and every row share one column count.
    pub rows: Vec<Vec<String>>,
}

impl MarkdownTable {
    pub fn column_count(&self) -> usize {
        self.header.len()
    }
}

// MARK: - Parser

pub fn parse(text: &str) -> Vec<MarkdownBlock> {
    if text.is_empty() {
        return Vec::new();
    }
    let normalized = if text.contains('\r') {
        text.replace("\r\n", "\n").replace('\r', "\n")
    } else {
        text.to_owned()
    };
    let lines: Vec<String> = normalized.split('\n').map(expand_leading_tabs).collect();
    parse_blocks(&lines, 0)
}

fn parse_blocks(lines: &[String], depth: usize) -> Vec<MarkdownBlock> {
    let mut blocks = Vec::new();
    let mut paragraph: Vec<String> = Vec::new();

    fn flush(blocks: &mut Vec<MarkdownBlock>, paragraph: &mut Vec<String>) {
        if paragraph.is_empty() {
            return;
        }
        blocks.push(MarkdownBlock::Paragraph(paragraph.join("\n")));
        paragraph.clear();
    }

    let mut i = 0;
    while i < lines.len() {
        let line = &lines[i];
        if is_blank(line) {
            flush(&mut blocks, &mut paragraph);
            i += 1;
            continue;
        }
        if let Some(fence) = opening_fence(line) {
            flush(&mut blocks, &mut paragraph);
            let (block, next) = parse_fenced_code(lines, i, &fence);
            blocks.push(block);
            i = next;
            continue;
        }
        if !paragraph.is_empty() {
            if let Some(level) = setext_level(line) {
                blocks.push(MarkdownBlock::Heading {
                    level,
                    text: paragraph.join(" "),
                });
                paragraph.clear();
                i += 1;
                continue;
            }
        }
        if let Some((level, text)) = atx_heading(line) {
            flush(&mut blocks, &mut paragraph);
            blocks.push(MarkdownBlock::Heading { level, text });
            i += 1;
            continue;
        }
        if is_thematic_break(line) {
            flush(&mut blocks, &mut paragraph);
            blocks.push(MarkdownBlock::ThematicBreak);
            i += 1;
            continue;
        }
        if let Some((table, next)) = parse_table(lines, i) {
            flush(&mut blocks, &mut paragraph);
            blocks.push(MarkdownBlock::Table(table));
            i = next;
            continue;
        }
        if quote_content(line).is_some() {
            flush(&mut blocks, &mut paragraph);
            let (block, next) = parse_quote(lines, i, depth);
            blocks.push(block);
            i = next;
            continue;
        }
        if let Some(marker) = list_marker(line) {
            if paragraph.is_empty() || marker.can_interrupt_paragraph() {
                flush(&mut blocks, &mut paragraph);
                let (block, next) = parse_list(lines, i, &marker, depth);
                blocks.push(block);
                i = next;
                continue;
            }
        }
        paragraph.push(trim(line).to_owned());
        i += 1;
    }
    flush(&mut blocks, &mut paragraph);
    blocks
}

/// True when `lines[index]` opens a block that ends a lazy continuation (the
/// unindented follow-on lines a list item or quote may absorb).
fn starts_block(lines: &[String], index: usize) -> bool {
    let line = &lines[index];
    opening_fence(line).is_some()
        || atx_heading(line).is_some()
        || is_thematic_break(line)
        || quote_content(line).is_some()
        || list_marker(line).is_some()
        || table_header(lines, index).is_some()
}

/// Whether a line leaves an open paragraph behind it — the precondition for
/// the next line to be a lazy continuation of that paragraph.
fn continues_paragraph(line: &str) -> bool {
    !is_blank(line)
        && opening_fence(line).is_none()
        && atx_heading(line).is_none()
        && !is_thematic_break(line)
}

// MARK: Rendered fenced code

#[derive(Clone, Debug, PartialEq, Eq)]
struct Fence {
    marker: char,
    length: usize,
    indent: usize,
    info: String,
}

fn opening_fence(line: &str) -> Option<Fence> {
    let indent = indentation(line);
    let rest: Vec<char> = line.chars().skip(indent).collect();
    let marker = *rest.first()?;
    if marker != '`' && marker != '~' {
        return None;
    }
    let length = rest.iter().take_while(|c| **c == marker).count();
    if length < 3 {
        return None;
    }
    let info = trim(&chars_to_string(&rest[length..])).to_owned();
    // ```code``` on one line is an inline code span, not a fence.
    if marker == '`' && info.contains('`') {
        return None;
    }
    Some(Fence {
        marker,
        length,
        indent,
        info,
    })
}

fn closes_fence(line: &str, fence: &Fence) -> bool {
    // CommonMark caps the closing fence's indent at three spaces; models
    // indent it to match whatever the code sat under, so accept any.
    let trimmed: Vec<char> = trim(line).chars().collect();
    trimmed.len() >= fence.length && trimmed.iter().all(|c| *c == fence.marker)
}

fn parse_fenced_code(lines: &[String], start: usize, fence: &Fence) -> (MarkdownBlock, usize) {
    let mut body: Vec<String> = Vec::new();
    let mut closed = false;
    let mut i = start + 1;
    while i < lines.len() {
        if closes_fence(&lines[i], fence) {
            closed = true;
            i += 1;
            break;
        }
        body.push(drop_indent(&lines[i], fence.indent));
        i += 1;
    }
    // Trailing blank lines only add dead space under the code; streaming
    // replies produce them whenever a chunk ends right after a newline.
    while body.last().is_some_and(|last| is_blank(last)) {
        body.pop();
    }
    let language = fence
        .info
        .split([' ', '\t'])
        .find(|word| !word.is_empty())
        .map(str::to_owned);
    (
        MarkdownBlock::Code(MarkdownCodeBlock {
            language,
            code: body.join("\n"),
            is_closed: closed,
        }),
        i,
    )
}

// MARK: Headings, breaks

fn atx_heading(line: &str) -> Option<(usize, String)> {
    let indent = indentation(line);
    if indent > 3 {
        return None;
    }
    let rest: Vec<char> = line.chars().skip(indent).collect();
    let level = rest.iter().take_while(|c| **c == '#').count();
    if !(1..=6).contains(&level) {
        return None;
    }
    let after = &rest[level..];
    // "#hashtag" is text; a heading needs whitespace (or nothing) after the #s.
    if after.first().is_some_and(|c| *c != ' ' && *c != '\t') {
        return None;
    }
    let text = trim(&chars_to_string(after)).to_owned();
    if text.chars().all(|c| c == '#') {
        return Some((level, String::new()));
    }
    Some((level, dropping_closing_sequence(&text)))
}

/// "Title ##" → "Title": a closing run of `#`s counts only after a space or
/// tab ("C#" keeps its #). Scans back from the end once — the regex
/// `[ \t]+#+$` this replaces retried from every blank, quadratic in a long
/// run of spaces, and parsing runs on the main thread.
fn dropping_closing_sequence(text: &str) -> String {
    let chars: Vec<char> = text.chars().collect();
    let mut hashes_start = chars.len();
    while hashes_start > 0 && chars[hashes_start - 1] == '#' {
        hashes_start -= 1;
    }
    if hashes_start == chars.len() || hashes_start == 0 {
        return text.to_owned();
    }
    let mut content_end = hashes_start;
    while content_end > 0 {
        let previous = chars[content_end - 1];
        if previous != ' ' && previous != '\t' {
            break;
        }
        content_end -= 1;
    }
    if content_end < hashes_start {
        chars_to_string(&chars[..content_end])
    } else {
        text.to_owned()
    }
}

/// `===` / `---` under a paragraph. CommonMark accepts a single `-`, but
/// that's also how every streamed bullet list starts ("Files:\n-"), which
/// would flash the line above as a heading; require three characters.
fn setext_level(line: &str) -> Option<usize> {
    if indentation(line) > 3 {
        return None;
    }
    let trimmed: Vec<char> = trim(line).chars().collect();
    if trimmed.len() < 3 {
        return None;
    }
    if trimmed.iter().all(|c| *c == '=') {
        return Some(1);
    }
    if trimmed.iter().all(|c| *c == '-') {
        return Some(2);
    }
    None
}

fn is_thematic_break(line: &str) -> bool {
    if indentation(line) > 3 {
        return false;
    }
    let mut marker: Option<char> = None;
    let mut count = 0;
    for ch in line.chars().filter(|c| *c != ' ' && *c != '\t') {
        if ch != '-' && ch != '*' && ch != '_' {
            return false;
        }
        if marker.is_some_and(|m| m != ch) {
            return false;
        }
        marker = Some(ch);
        count += 1;
    }
    count >= 3
}

// MARK: Block quotes

/// The line's content after its `>` marker, or `None` for a non-quote line.
fn quote_content(line: &str) -> Option<String> {
    let indent = indentation(line);
    if indent > 3 {
        return None;
    }
    let rest: Vec<char> = line.chars().skip(indent).collect();
    if rest.first() != Some(&'>') {
        return None;
    }
    let mut content = &rest[1..];
    if content.first() == Some(&' ') {
        content = &content[1..];
    }
    Some(chars_to_string(content))
}

fn parse_quote(lines: &[String], start: usize, depth: usize) -> (MarkdownBlock, usize) {
    let mut body: Vec<String> = Vec::new();
    let mut lazy_allowed = false;
    let mut i = start;
    while i < lines.len() {
        let line = &lines[i];
        if is_blank(line) {
            break;
        }
        if let Some(content) = quote_content(line) {
            lazy_allowed = continues_paragraph(&content);
            body.push(content);
        } else if lazy_allowed && !starts_block(lines, i) {
            body.push(trim(line).to_owned());
        } else {
            break;
        }
        i += 1;
    }
    if depth + 1 >= MAX_NESTING_DEPTH {
        return (MarkdownBlock::Quote(flattened_paragraph(&body)), i);
    }
    (MarkdownBlock::Quote(parse_blocks(&body, depth + 1)), i)
}

// MARK: Lists

#[derive(Clone, Debug, PartialEq, Eq)]
struct ListMarker {
    indent: usize,
    is_ordered: bool,
    number: i64,
    /// Column where the item's content starts; continuation lines indented
    /// this far belong to the item.
    content_offset: usize,
    content: String,
}

impl ListMarker {
    /// CommonMark: a list may interrupt a paragraph only with a non-empty
    /// item, and an ordered one only when it starts at 1 — otherwise
    /// "…was released in\n2024. It…" would turn into a list.
    fn can_interrupt_paragraph(&self) -> bool {
        !self.content.is_empty() && (!self.is_ordered || self.number == 1)
    }
}

fn list_marker(line: &str) -> Option<ListMarker> {
    let indent = indentation(line);
    let rest: Vec<char> = line.chars().skip(indent).collect();
    // Called on nearly every line, often more than once: look at just enough
    // characters for the longest marker ("123456789.") and its space.
    let head: Vec<char> = rest.iter().take(11).copied().collect();
    let first = *head.first()?;

    let marker_width;
    let mut is_ordered = false;
    let mut number = 1;
    if first == '-' || first == '*' || first == '+' {
        marker_width = 1;
    } else if first.is_ascii_digit() {
        let mut digits = 0;
        while digits < head.len() && digits < 9 && head[digits].is_ascii_digit() {
            digits += 1;
        }
        if digits >= head.len() || (head[digits] != '.' && head[digits] != ')') {
            return None;
        }
        number = chars_to_string(&head[..digits]).parse().unwrap_or(1);
        marker_width = digits + 1;
        is_ordered = true;
    } else {
        return None;
    }
    // "**bold**", "-1", "1.5x": the marker must be followed by whitespace.
    if marker_width < head.len() && head[marker_width] != ' ' && head[marker_width] != '\t' {
        return None;
    }

    let after_marker: Vec<char> = rest.iter().skip(marker_width).copied().collect();
    let spaces = after_marker
        .iter()
        .take_while(|c| **c == ' ' || **c == '\t')
        .count();
    let content = trim(&chars_to_string(&after_marker[spaces..])).to_owned();
    // Five or more spaces would make the content an indented code block in
    // CommonMark; we don't render those, so count just the one space.
    let padding = if spaces == 0 || spaces > 4 || content.is_empty() {
        1
    } else {
        spaces
    };
    Some(ListMarker {
        indent,
        is_ordered,
        number,
        content_offset: indent + marker_width + padding,
        content,
    })
}

fn parse_list(
    lines: &[String],
    start: usize,
    first: &ListMarker,
    depth: usize,
) -> (MarkdownBlock, usize) {
    let mut items: Vec<MarkdownListItem> = Vec::new();
    let mut marker = first.clone();
    let mut i = start;
    loop {
        let (body, next) = collect_item_lines(lines, i, &marker);
        items.push(make_item(&body, depth));
        i = next;

        // Blank lines between items make a loose list, not a new one.
        let mut k = next;
        while k < lines.len() && is_blank(&lines[k]) {
            k += 1;
        }
        let sibling = if k < lines.len() && !is_thematic_break(&lines[k]) {
            list_marker(&lines[k]).filter(|sibling| sibling.is_ordered == first.is_ordered)
        } else {
            None
        };
        match sibling {
            Some(sibling) => {
                marker = sibling;
                i = k;
            }
            None => break,
        }
    }
    (
        MarkdownBlock::List(MarkdownList {
            is_ordered: first.is_ordered,
            start: first.number,
            items,
        }),
        i,
    )
}

/// Gathers one item's lines, dedented, starting with the text after its
/// marker. Returns the index of the first line that isn't part of it.
fn collect_item_lines(lines: &[String], start: usize, marker: &ListMarker) -> (Vec<String>, usize) {
    // CommonMark nests a child only once it reaches the parent's content
    // column ("1. " → 3). Models routinely nest by two spaces whatever the
    // marker width, so two past the marker is enough too.
    let child_indent = marker.content_offset.min(marker.indent + 2);
    let mut body = vec![marker.content.clone()];
    let mut open_fence = opening_fence(&marker.content);
    let mut lazy_allowed = open_fence.is_none() && continues_paragraph(&marker.content);
    let mut pending_blanks = 0;
    let mut i = start + 1;

    while i < lines.len() {
        let line = &lines[i];
        if let Some(fence) = open_fence.clone() {
            // Everything up to the closing fence is code, however it is
            // indented: an under-indented sample must not escape the item and
            // leave its closing fence to re-open as a runaway block.
            body.extend(std::iter::repeat_n(String::new(), pending_blanks));
            pending_blanks = 0;
            body.push(drop_indent(line, child_indent));
            if closes_fence(line, &fence) {
                open_fence = None;
            }
            lazy_allowed = false;
            i += 1;
            continue;
        }
        if is_blank(line) {
            pending_blanks += 1;
            i += 1;
            continue;
        }
        if indentation(line) >= child_indent {
            body.extend(std::iter::repeat_n(String::new(), pending_blanks));
            pending_blanks = 0;
            let dedented = drop_indent(line, child_indent);
            open_fence = opening_fence(&dedented);
            lazy_allowed = open_fence.is_none() && continues_paragraph(&dedented);
            body.push(dedented);
            i += 1;
            continue;
        }
        if pending_blanks == 0 && lazy_allowed && !starts_block(lines, i) {
            body.push(trim(line).to_owned());
            i += 1;
            continue;
        }
        break;
    }
    // Trailing blank lines separate this item from what follows; leave them
    // for the caller.
    (body, i - pending_blanks)
}

fn make_item(lines: &[String], depth: usize) -> MarkdownListItem {
    let mut lines = lines.to_vec();
    let mut checkbox = None;
    if let Some((box_, rest)) = lines.first().and_then(|first| task_checkbox(first)) {
        checkbox = Some(box_);
        lines[0] = rest;
    }
    let blocks = if depth + 1 >= MAX_NESTING_DEPTH {
        flattened_paragraph(&lines)
    } else {
        parse_blocks(&lines, depth + 1)
    };
    MarkdownListItem { checkbox, blocks }
}

fn task_checkbox(content: &str) -> Option<(Checkbox, String)> {
    if content.chars().count() < 3 || !content.starts_with('[') {
        return None;
    }
    let chars: Vec<char> = content.chars().take(4).collect();
    if chars.get(2) != Some(&']') {
        return None;
    }
    let checkbox = match chars[1] {
        ' ' => Checkbox::Unchecked,
        'x' | 'X' => Checkbox::Checked,
        _ => return None,
    };
    // "[x]" must stand alone or be followed by whitespace; "[x](url)" is a link.
    if chars.len() == 4 && chars[3] != ' ' && chars[3] != '\t' {
        return None;
    }
    let rest: Vec<char> = content.chars().skip(3).collect();
    Some((checkbox, trim(&chars_to_string(&rest)).to_owned()))
}

// MARK: Tables

/// Header cells and alignments when `lines[index]` starts a GFM table: a row
/// with a pipe followed by a delimiter row (`| --- | :-: |`).
fn table_header(
    lines: &[String],
    index: usize,
) -> Option<(Vec<String>, Vec<MarkdownTableAlignment>)> {
    if index + 1 >= lines.len() {
        return None;
    }
    let header_line = &lines[index];
    if !header_line.contains('|') || indentation(header_line) > 3 {
        return None;
    }
    let delimiter_line = &lines[index + 1];
    if !delimiter_line.contains('|')
        || !delimiter_line
            .chars()
            .all(|c| c == '|' || c == '-' || c == ':' || c == ' ' || c == '\t')
    {
        return None;
    }
    let delimiter_cells = split_row(delimiter_line);
    let mut alignments = Vec::with_capacity(delimiter_cells.len());
    let mut complete = true;
    for cell in &delimiter_cells {
        match delimiter_alignment(cell) {
            Some(alignment) => alignments.push(alignment),
            None => {
                complete = false;
                alignments.push(MarkdownTableAlignment::Automatic);
            }
        }
    }
    // A streaming reply ends mid-delimiter ("|---|--" or just "|") until the
    // next chunk lands; show the table already rather than flashing raw
    // pipes. Any earlier line has to be a well-formed delimiter.
    let is_last_line = index + 1 == lines.len() - 1;
    if !complete && !is_last_line {
        return None;
    }
    Some((split_row(header_line), alignments))
}

fn delimiter_alignment(cell: &str) -> Option<MarkdownTableAlignment> {
    let chars: Vec<char> = cell.chars().collect();
    let leading = chars.first() == Some(&':');
    let trailing = chars.len() > 1 && chars.last() == Some(&':');
    let dashes = &chars[usize::from(leading)..chars.len() - usize::from(trailing)];
    if dashes.is_empty() || !dashes.iter().all(|c| *c == '-') {
        return None;
    }
    Some(match (leading, trailing) {
        (true, true) => MarkdownTableAlignment::Center,
        (true, false) => MarkdownTableAlignment::Leading,
        (false, true) => MarkdownTableAlignment::Trailing,
        (false, false) => MarkdownTableAlignment::Automatic,
    })
}

fn parse_table(lines: &[String], start: usize) -> Option<(MarkdownTable, usize)> {
    let (header, delimiter_alignments) = table_header(lines, start)?;
    let mut rows: Vec<Vec<String>> = Vec::new();
    let mut i = start + 2;
    while i < lines.len() {
        let line = &lines[i];
        if is_blank(line)
            || !line.contains('|')
            || opening_fence(line).is_some()
            || atx_heading(line).is_some()
            || quote_content(line).is_some()
        {
            break;
        }
        rows.push(split_row(line));
        i += 1;
    }
    // GFM clips cells beyond the header's count; widen the table instead so a
    // model's miscounted row never silently loses content — up to
    // MAX_TABLE_COLUMNS: a stray line of pipes would otherwise make hundreds
    // of columns and tens of thousands of cells.
    let widest = std::iter::once(header.len())
        .chain(std::iter::once(delimiter_alignments.len()))
        .chain(rows.iter().map(Vec::len))
        .max()
        .unwrap_or(0);
    let column_count = widest.min(MAX_TABLE_COLUMNS);
    let fitted = |cells: &Vec<String>| -> Vec<String> {
        if cells.len() <= column_count {
            let mut out = cells.clone();
            out.resize(column_count, String::new());
            return out;
        }
        // The overflow stays readable in the last column, pipes and all.
        let mut out: Vec<String> = cells[..column_count - 1].to_vec();
        let rest: Vec<String> = cells[column_count - 1..]
            .iter()
            .filter(|cell| !cell.is_empty())
            .cloned()
            .collect();
        out.push(rest.join(" | "));
        out
    };
    let mut alignments: Vec<MarkdownTableAlignment> = delimiter_alignments
        .iter()
        .take(column_count)
        .copied()
        .collect();
    alignments.resize(column_count, MarkdownTableAlignment::Automatic);
    let table = MarkdownTable {
        header: fitted(&header),
        alignments,
        rows: rows.iter().map(fitted).collect(),
    };
    Some((table, i))
}

/// Splits a table row on unescaped pipes. Pipes inside `code spans` stay in
/// their cell even unescaped — GFM would split there, but models write
/// `a | b` in code all the time and a torn cell is worse than a lenient one.
pub fn split_row(line: &str) -> Vec<String> {
    let trimmed = trim(line);
    let mut row: Vec<char> = trimmed.chars().collect();
    if row.first() == Some(&'|') {
        row.remove(0);
    }
    if row.last() == Some(&'|') && !trimmed.ends_with("\\|") {
        row.pop();
    }

    let mut cells: Vec<String> = Vec::new();
    let mut current = String::new();
    let mut k = 0;
    while k < row.len() {
        let ch = row[k];
        if ch == '\\' && k + 1 < row.len() && row[k + 1] == '|' {
            current.push('|');
            k += 2;
        } else if ch == '`' {
            let mut run = 0;
            while k + run < row.len() && row[k + run] == '`' {
                run += 1;
            }
            let end = closing_backtick_run(&row, k + run, run).map_or(k + run, |found| found + run);
            let span: String = row[k..end].iter().collect();
            current.push_str(&span.replace("\\|", "|"));
            k = end;
        } else if ch == '|' {
            cells.push(trim(&current).to_owned());
            current.clear();
            k += 1;
        } else {
            current.push(ch);
            k += 1;
        }
    }
    cells.push(trim(&current).to_owned());
    cells
}

fn closing_backtick_run(chars: &[char], from: usize, length: usize) -> Option<usize> {
    let mut k = from;
    while k < chars.len() {
        if chars[k] != '`' {
            k += 1;
            continue;
        }
        let mut run = 0;
        while k + run < chars.len() && chars[k + run] == '`' {
            run += 1;
        }
        if run == length {
            return Some(k);
        }
        k += run;
    }
    None
}

// MARK: Helpers

fn flattened_paragraph(lines: &[String]) -> Vec<MarkdownBlock> {
    let text = lines
        .iter()
        .map(|line| trim(line))
        .filter(|line| !line.is_empty())
        .collect::<Vec<_>>()
        .join("\n");
    if text.is_empty() {
        Vec::new()
    } else {
        vec![MarkdownBlock::Paragraph(text)]
    }
}

fn is_blank(line: &str) -> bool {
    line.chars().all(|c| c == ' ' || c == '\t')
}

fn indentation(line: &str) -> usize {
    line.chars().take_while(|c| *c == ' ').count()
}

fn drop_indent(line: &str, up_to: usize) -> String {
    let dropped = indentation(line).min(up_to);
    line.chars().skip(dropped).collect()
}

/// Leading tabs become spaces (to the next multiple of four) so indentation
/// can be compared by counting spaces alone.
fn expand_leading_tabs(line: &str) -> String {
    let chars: Vec<char> = line.chars().collect();
    let starts_indented = matches!(chars.first(), Some(' ' | '\t'));
    if !starts_indented || !chars.contains(&'\t') {
        return line.to_owned();
    }
    let mut prefix = String::new();
    let mut index = 0;
    while index < chars.len() && (chars[index] == ' ' || chars[index] == '\t') {
        if chars[index] == '\t' {
            let width = prefix.chars().count();
            prefix.extend(std::iter::repeat_n(' ', 4 - width % 4));
        } else {
            prefix.push(' ');
        }
        index += 1;
    }
    prefix + &chars[index..].iter().collect::<String>()
}

/// `String.trimmingCharacters(in: .whitespaces)`: spaces, tabs and the other
/// whitespace scalars, but no newline — the parser hands in single lines.
fn trim(text: &str) -> &str {
    text.trim_matches(|c: char| c.is_whitespace() && c != '\n')
}

fn chars_to_string(chars: &[char]) -> String {
    chars.iter().collect()
}
