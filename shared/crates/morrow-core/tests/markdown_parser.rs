//! `MarkdownBlockParserTests` (`macos/Tests/MorrowCoreTests/MarkdownBlockParserTests.swift`),
//! ported one test to one test: every reply-shaped input the Swift suite pins
//! must give the same blocks here.
//!
//! Two Swift tests have no counterpart: `testCachedBlocksMatchTheParser`
//! (the cache is `ChatMessageTextFormatter`'s, in the macOS app) and the
//! `[bench]` print inside the large-reply test.

use std::collections::HashSet;
use std::time::Instant;

use morrow_core::markdown::{
    Checkbox, MAX_NESTING_DEPTH, MAX_TABLE_COLUMNS, MarkdownBlock, MarkdownCodeBlock, MarkdownList,
    MarkdownTable, MarkdownTableAlignment, parse,
};

// MARK: - Helpers

fn strings(cells: &[&str]) -> Vec<String> {
    cells.iter().map(|cell| (*cell).to_owned()).collect()
}

fn rows(cells: &[&[&str]]) -> Vec<Vec<String>> {
    cells.iter().map(|row| strings(row)).collect()
}

fn heading(level: usize, text: &str) -> MarkdownBlock {
    MarkdownBlock::Heading {
        level,
        text: text.to_owned(),
    }
}

fn paragraph(text: &str) -> MarkdownBlock {
    MarkdownBlock::Paragraph(text.to_owned())
}

fn code(language: Option<&str>, body: &str, is_closed: bool) -> MarkdownBlock {
    MarkdownBlock::Code(MarkdownCodeBlock {
        language: language.map(str::to_owned),
        code: body.to_owned(),
        is_closed,
    })
}

fn list(block: Option<&MarkdownBlock>) -> &MarkdownList {
    match block {
        Some(MarkdownBlock::List(list)) => list,
        other => panic!("expected a list, got {other:?}"),
    }
}

fn table(block: Option<&MarkdownBlock>) -> &MarkdownTable {
    match block {
        Some(MarkdownBlock::Table(table)) => table,
        other => panic!("expected a table, got {other:?}"),
    }
}

fn code_block(block: Option<&MarkdownBlock>) -> &MarkdownCodeBlock {
    match block {
        Some(MarkdownBlock::Code(code)) => code,
        other => panic!("expected a code block, got {other:?}"),
    }
}

// MARK: - Headings & paragraphs

#[test]
fn empty_and_blank_input_produce_no_blocks() {
    assert_eq!(parse(""), []);
    assert_eq!(parse("  \n\n\t\n"), []);
}

#[test]
fn atx_headings_strip_markers_and_closing_sequence() {
    assert_eq!(parse("# Title"), [heading(1, "Title")]);
    assert_eq!(parse("### Sub section ##"), [heading(3, "Sub section")]);
    assert_eq!(parse("## C#"), [heading(2, "C#")]);
    // A streamed lone # is an empty heading, not a crash.
    assert_eq!(parse("#"), [heading(1, "")]);
}

#[test]
fn closing_sequence_needs_a_blank_before_it() {
    assert_eq!(parse("# Title\t###"), [heading(1, "Title")]);
    assert_eq!(parse("# a # b ##"), [heading(1, "a # b")]);
    // An escaped # is text.
    assert_eq!(parse("# issue \\#"), [heading(1, "issue \\#")]);
    assert_eq!(parse("## ## #"), [heading(2, "##")]);
    assert_eq!(parse("## ###"), [heading(2, "")]);
}

#[test]
fn heading_with_a_long_run_of_blanks_parses_in_linear_time() {
    // The closing-sequence regex retried from every blank: 5 000 spaces took
    // ~0.5s and 20 000 about 10s, on the main thread.
    let heading_text = format!("# a{}b", " ".repeat(20_000));
    let start = Instant::now();
    let blocks = parse(&heading_text);
    let elapsed_ms = start.elapsed().as_secs_f64() * 1000.0;
    assert_eq!(blocks, [heading(1, &format!("a{}b", " ".repeat(20_000)))]);
    assert!(elapsed_ms < 50.0, "took {elapsed_ms} ms");

    let tabs = format!("## x{}y", "\t".repeat(20_000));
    let start = Instant::now();
    parse(&tabs);
    let elapsed_ms = start.elapsed().as_secs_f64() * 1000.0;
    assert!(elapsed_ms < 50.0, "took {elapsed_ms} ms");
}

#[test]
fn hash_without_space_or_too_many_hashes_is_text() {
    assert_eq!(parse("#hashtag"), [paragraph("#hashtag")]);
    assert_eq!(parse("####### seven"), [paragraph("####### seven")]);
}

#[test]
fn setext_headings() {
    assert_eq!(parse("Title\n==="), [heading(1, "Title")]);
    assert_eq!(parse("Sub\n---"), [heading(2, "Sub")]);
}

#[test]
fn streamed_bullet_start_does_not_turn_previous_line_into_heading() {
    // "Files:\n-" is what a reply looks like one chunk before "- a.swift".
    assert_eq!(parse("Files:\n-"), [paragraph("Files:\n-")]);
}

#[test]
fn paragraphs_keep_line_breaks_and_split_on_blank_lines() {
    assert_eq!(
        parse("first line\n  second line  \n\nnext paragraph"),
        [
            paragraph("first line\nsecond line"),
            paragraph("next paragraph")
        ]
    );
}

#[test]
fn thematic_breaks() {
    for rule in ["---", "***", "___", "- - -", " * * * "] {
        assert_eq!(
            parse(&format!("a\n\n{rule}\n\nb")),
            [paragraph("a"), MarkdownBlock::ThematicBreak, paragraph("b")],
            "{rule}"
        );
    }
}

// MARK: - Lists

#[test]
fn bullet_list_with_mixed_markers() {
    let blocks = parse("- one\n* two\n+ three");
    let outer = list(blocks.first());
    assert!(!outer.is_ordered);
    assert_eq!(
        outer
            .items
            .iter()
            .map(|item| item.blocks.clone())
            .collect::<Vec<_>>(),
        [
            vec![paragraph("one")],
            vec![paragraph("two")],
            vec![paragraph("three")]
        ]
    );
}

#[test]
fn ordered_list_keeps_its_start_number() {
    let blocks = parse("3. three\n4) four");
    let outer = list(blocks.first());
    assert!(outer.is_ordered);
    assert_eq!(outer.start, 3);
    assert_eq!(outer.items.len(), 2);
}

#[test]
fn only_a_list_starting_at_one_interrupts_a_paragraph() {
    assert_eq!(
        parse("It was released in\n2024. It sold well."),
        [paragraph("It was released in\n2024. It sold well.")]
    );

    let blocks = parse("Steps:\n1. build\n2. test");
    assert_eq!(blocks.first(), Some(&paragraph("Steps:")));
    assert_eq!(list(blocks.last()).items.len(), 2);
}

#[test]
fn marker_lookalikes_stay_text() {
    assert_eq!(parse("**bold** start"), [paragraph("**bold** start")]);
    assert_eq!(parse("-1 degrees"), [paragraph("-1 degrees")]);
    assert_eq!(parse("1.5x faster"), [paragraph("1.5x faster")]);
}

#[test]
fn nested_bullet_lists() {
    let blocks = parse("- a\n  - b\n    - c\n- d");
    let outer = list(blocks.first());
    assert_eq!(blocks.len(), 1);
    assert_eq!(outer.items.len(), 2);
    assert_eq!(outer.items[0].blocks.first(), Some(&paragraph("a")));
    let middle = list(outer.items[0].blocks.last());
    assert_eq!(middle.items[0].blocks.first(), Some(&paragraph("b")));
    let inner = list(middle.items[0].blocks.last());
    assert_eq!(
        inner
            .items
            .iter()
            .map(|item| item.blocks.clone())
            .collect::<Vec<_>>(),
        [vec![paragraph("c")]]
    );
    assert_eq!(outer.items[1].blocks, [paragraph("d")]);
}

#[test]
fn two_space_nesting_under_ordered_item() {
    // CommonMark wants three spaces under "1. "; models routinely use two.
    let blocks = parse("1. first\n  - detail\n2. second");
    let outer = list(blocks.first());
    assert_eq!(outer.items.len(), 2);
    assert!(matches!(
        outer.items[0].blocks.last(),
        Some(MarkdownBlock::List(_))
    ));
}

#[test]
fn one_space_indent_is_a_sibling_not_a_child() {
    let blocks = parse("- a\n - b");
    assert_eq!(list(blocks.first()).items.len(), 2);
}

#[test]
fn task_list_items() {
    let blocks = parse("- [ ] todo\n- [x] done\n- [X] also done\n- [link](https://x.dev)\n- [x]");
    let outer = list(blocks.first());
    assert_eq!(
        outer
            .items
            .iter()
            .map(|item| item.checkbox)
            .collect::<Vec<_>>(),
        [
            Some(Checkbox::Unchecked),
            Some(Checkbox::Checked),
            Some(Checkbox::Checked),
            None,
            Some(Checkbox::Checked)
        ]
    );
    assert_eq!(outer.items[0].blocks, [paragraph("todo")]);
    assert_eq!(outer.items[3].blocks, [paragraph("[link](https://x.dev)")]);
    // A streamed bare checkbox has no text yet.
    assert_eq!(outer.items[4].blocks, []);
}

#[test]
fn blank_lines_between_items_keep_one_list() {
    let blocks = parse("- a\n\n- b\n\n\n- c");
    assert_eq!(list(blocks.first()).items.len(), 3);
}

#[test]
fn switching_between_bullet_and_ordered_starts_a_new_list() {
    let blocks = parse("- a\n1. b");
    assert_eq!(blocks.len(), 2);
    assert!(!list(blocks.first()).is_ordered);
    assert!(list(blocks.get(1)).is_ordered);
}

#[test]
fn lazy_continuation_stays_in_item() {
    let blocks = parse("- first\ncontinued\n- second");
    let outer = list(blocks.first());
    assert_eq!(outer.items[0].blocks, [paragraph("first\ncontinued")]);
    assert_eq!(outer.items.len(), 2);
}

#[test]
fn paragraph_after_blank_line_ends_list() {
    let blocks = parse("- a\n\nafter");
    assert_eq!(blocks.len(), 2);
    assert_eq!(blocks.last(), Some(&paragraph("after")));
}

#[test]
fn list_item_with_indented_fenced_code() {
    let blocks = parse("1. Run:\n   ```sh\n   npm i\n\n   npm test\n   ```\n2. Next");
    let outer = list(blocks.first());
    assert_eq!(blocks.len(), 1);
    assert_eq!(outer.items.len(), 2);
    assert_eq!(outer.items[0].blocks.first(), Some(&paragraph("Run:")));
    assert_eq!(
        outer.items[0].blocks.last(),
        Some(&code(Some("sh"), "npm i\n\nnpm test", true))
    );
}

#[test]
fn under_indented_code_inside_list_item_does_not_run_away() {
    // The body and closing fence sit at column 0; without fence tracking the
    // closer would re-open as a fence that swallows "2. Next".
    let blocks = parse("1. Run:\n   ```sh\nnpm i\n```\n2. Next");
    let outer = list(blocks.first());
    assert_eq!(blocks.len(), 1);
    assert_eq!(outer.items.len(), 2);
    assert_eq!(code_block(outer.items[0].blocks.last()).code, "npm i");
    assert_eq!(outer.items[1].blocks, [paragraph("Next")]);
}

#[test]
fn unindented_fence_after_item_ends_the_list() {
    let blocks = parse("1. Run:\n```sh\nnpm i\n```");
    assert_eq!(blocks.len(), 2);
    assert_eq!(list(blocks.first()).items.len(), 1);
    assert_eq!(code_block(blocks.last()).code, "npm i");
}

// MARK: - Fenced code

#[test]
fn fenced_code_keeps_language_and_indentation() {
    let blocks = parse("```swift title=\"x.swift\"\nfunc a() {\n    b()\n}\n```");
    assert_eq!(
        code_block(blocks.first()),
        &MarkdownCodeBlock {
            language: Some("swift".into()),
            code: "func a() {\n    b()\n}".into(),
            is_closed: true,
        }
    );
}

#[test]
fn fenced_code_interrupts_paragraph_and_leaves_inline_syntax_alone() {
    let blocks = parse("Run the following:\n```\nvar x = *y* + `z`\n```\nand you're done.");
    assert_eq!(
        blocks,
        [
            paragraph("Run the following:"),
            code(None, "var x = *y* + `z`", true),
            paragraph("and you're done."),
        ]
    );
}

#[test]
fn tilde_and_longer_fences_nest_shorter_fences() {
    assert_eq!(
        code_block(parse("~~~\na ``` b\n~~~").first()).code,
        "a ``` b"
    );
    let parsed = parse("````md\n```js\nx\n```\n````");
    let nested = code_block(parsed.first());
    assert_eq!(
        nested,
        &MarkdownCodeBlock {
            language: Some("md".into()),
            code: "```js\nx\n```".into(),
            is_closed: true,
        }
    );
}

#[test]
fn fence_closes_only_on_a_bare_fence_line() {
    let blocks = parse("```\na\n``` not a close\n```");
    assert_eq!(code_block(blocks.first()).code, "a\n``` not a close");
}

#[test]
fn indented_fence_strips_its_indent_from_the_body() {
    let blocks = parse("  ```\n  one\n    two\n  ```");
    assert_eq!(code_block(blocks.first()).code, "one\n  two");
}

#[test]
fn triple_backtick_span_on_one_line_is_not_a_fence() {
    assert_eq!(parse("```let x = 1```"), [paragraph("```let x = 1```")]);
}

#[test]
fn streaming_unclosed_fence_keeps_its_content() {
    let blocks = parse("Here:\n```py\nprint(1)\nprint(2)\n\n");
    assert_eq!(blocks.first(), Some(&paragraph("Here:")));
    assert_eq!(
        blocks.last(),
        Some(&code(Some("py"), "print(1)\nprint(2)", false))
    );
}

#[test]
fn streaming_fence_opener_alone() {
    assert_eq!(parse("```"), [code(None, "", false)]);
    // Two backticks aren't a fence yet.
    assert_eq!(parse("text\n``"), [paragraph("text\n``")]);
}

// MARK: - Tables

#[test]
fn table_with_alignments() {
    let blocks = parse("| L | C | R | N |\n|:--|:-:|--:|---|\n| 1 | 2 | 3 | 4 |");
    let table = table(blocks.first());
    assert_eq!(table.header, strings(&["L", "C", "R", "N"]));
    assert_eq!(
        table.alignments,
        [
            MarkdownTableAlignment::Leading,
            MarkdownTableAlignment::Center,
            MarkdownTableAlignment::Trailing,
            MarkdownTableAlignment::Automatic
        ]
    );
    assert_eq!(table.rows, rows(&[&["1", "2", "3", "4"]]));
}

#[test]
fn table_without_outer_pipes() {
    let blocks = parse("name | size\n--- | ---:\na.swift | 10");
    let table = table(blocks.first());
    assert_eq!(table.header, strings(&["name", "size"]));
    assert_eq!(
        table.alignments,
        [
            MarkdownTableAlignment::Automatic,
            MarkdownTableAlignment::Trailing
        ]
    );
    assert_eq!(table.rows, rows(&[&["a.swift", "10"]]));
}

#[test]
fn table_cells_keep_escaped_pipes_and_pipes_inside_code_spans() {
    let blocks = parse("| a | b |\n|---|---|\n| `x | y` | c \\| d |");
    let table = table(blocks.first());
    assert_eq!(table.rows, rows(&[&["`x | y`", "c | d"]]));
}

#[test]
fn table_widens_instead_of_dropping_extra_cells() {
    let blocks = parse("| a | b |\n|---|---|\n| 1 |\n| 1 | 2 | 3 |");
    let table = table(blocks.first());
    assert_eq!(table.column_count(), 3);
    assert_eq!(table.header, strings(&["a", "b", ""]));
    assert_eq!(table.alignments.len(), 3);
    assert_eq!(table.rows, rows(&[&["1", "", ""], &["1", "2", "3"]]));
}

#[test]
fn stray_line_of_pipes_cannot_widen_a_table_without_bound() {
    // A line of 300 pipes under a table used to make it 299 columns wide.
    let body = (1..=200)
        .map(|n| format!("| {n} | row |"))
        .collect::<Vec<_>>()
        .join("\n");
    let text = format!("| a | b |\n|---|---|\n{body}\n{}", "|".repeat(300));
    let start = Instant::now();
    let blocks = parse(&text);
    let elapsed_ms = start.elapsed().as_secs_f64() * 1000.0;
    assert!(elapsed_ms < 200.0, "took {elapsed_ms} ms");
    let table = table(blocks.first());
    assert_eq!(table.column_count(), MAX_TABLE_COLUMNS);
    assert_eq!(table.alignments.len(), MAX_TABLE_COLUMNS);
    assert!(table.rows.iter().all(|row| row.len() == MAX_TABLE_COLUMNS));
    assert_eq!(table.rows.len(), 201);
    assert_eq!(
        table.rows.last(),
        Some(&vec![String::new(); MAX_TABLE_COLUMNS])
    );
}

#[test]
fn cells_past_the_column_cap_join_the_last_column() {
    let cells: Vec<String> = (1..=20).map(|n| format!("c{n}")).collect();
    let text = format!("| h |\n|---|\n| {} |", cells.join(" | "));
    let blocks = parse(&text);
    let table = table(blocks.first());
    let row = &table.rows[0];
    assert_eq!(row.len(), MAX_TABLE_COLUMNS);
    assert_eq!(&row[..15], &cells[..15]);
    // No cell is dropped.
    assert_eq!(
        row.last().map(String::as_str),
        Some("c16 | c17 | c18 | c19 | c20")
    );
}

#[test]
fn table_ends_at_blank_or_pipeless_line() {
    let blocks = parse("| a |\n|---|\n| 1 |\nafter\n\n| b |\n|---|\n| 2 |\n\nnext");
    assert_eq!(blocks.len(), 4);
    assert_eq!(table(blocks.first()).rows, rows(&[&["1"]]));
    assert_eq!(blocks[1], paragraph("after"));
    assert_eq!(table(blocks.get(2)).rows, rows(&[&["2"]]));
    assert_eq!(blocks[3], paragraph("next"));
}

#[test]
fn table_interrupts_a_paragraph() {
    let blocks = parse("Results:\n| a | b |\n|---|---|\n| 1 | 2 |");
    assert_eq!(blocks.first(), Some(&paragraph("Results:")));
    assert_eq!(table(blocks.last()).header, strings(&["a", "b"]));
}

#[test]
fn dashes_under_pipeless_text_are_a_heading_not_a_table() {
    assert_eq!(parse("a | b\n---"), [heading(2, "a | b")]);
}

#[test]
fn streaming_table_with_half_written_delimiter_row() {
    for partial in ["|", "|--", "| --- | :-"] {
        let text = format!("| a | b |\n{partial}");
        let blocks = parse(&text);
        let table = table(blocks.first());
        assert_eq!(table.header, strings(&["a", "b"]), "{partial}");
        assert_eq!(table.rows, Vec::<Vec<String>>::new(), "{partial}");
    }
}

#[test]
fn malformed_delimiter_followed_by_more_text_is_not_a_table() {
    assert_eq!(
        parse("| a | b |\n|--x\nmore"),
        [paragraph("| a | b |\n|--x\nmore")]
    );
    assert_eq!(
        parse("| a | b |\n|\nmore"),
        [paragraph("| a | b |\n|\nmore")]
    );
}

#[test]
fn lone_header_row_stays_a_paragraph() {
    assert_eq!(parse("| a | b |"), [paragraph("| a | b |")]);
}

#[test]
fn streaming_row_cut_mid_cell() {
    let blocks = parse("| a | b |\n|---|---|\n| 1 | tw");
    assert_eq!(table(blocks.first()).rows, rows(&[&["1", "tw"]]));
}

// MARK: - Quotes

#[test]
fn block_quote_with_lazy_continuation() {
    assert_eq!(
        parse("> **Note**\n> second\nlazy\n\nafter"),
        [
            MarkdownBlock::Quote(vec![paragraph("**Note**\nsecond\nlazy")]),
            paragraph("after")
        ]
    );
}

#[test]
fn block_quote_contains_blocks() {
    let blocks = parse("> # Title\n> - a\n> - b\n>\n> ```\n> code\n> ```");
    let MarkdownBlock::Quote(inner) = blocks.first().expect("a quote") else {
        panic!("expected quote, got {:?}", blocks.first());
    };
    assert_eq!(inner.first(), Some(&heading(1, "Title")));
    assert_eq!(list(inner.get(1)).items.len(), 2);
    assert_eq!(code_block(inner.last()).code, "code");
}

#[test]
fn nested_quotes() {
    assert_eq!(
        parse("> outer\n>> inner"),
        [MarkdownBlock::Quote(vec![
            paragraph("outer"),
            MarkdownBlock::Quote(vec![paragraph("inner")])
        ])]
    );
}

// MARK: - Robustness

#[test]
fn crlf_and_tab_indentation() {
    let blocks = parse("- a\r\n\t- b\r\n- c");
    let outer = list(blocks.first());
    assert_eq!(outer.items.len(), 2);
    assert!(matches!(
        outer.items[0].blocks.last(),
        Some(MarkdownBlock::List(_))
    ));
}

#[test]
fn deep_nesting_is_capped_without_losing_text() {
    let deep_list = (0..40)
        .map(|level| format!("{}- level{level}", "  ".repeat(level)))
        .collect::<Vec<_>>()
        .join("\n");
    let deep_quote = format!("{} bottom", ">".repeat(40));
    for text in [deep_list, deep_quote] {
        let blocks = parse(&text);
        assert!(max_depth(&blocks) <= MAX_NESTING_DEPTH + 1, "{text}");
        assert!(
            words(&text).is_subset(&words_of_blocks(&blocks)),
            "lost words in {text}"
        );
    }
}

/// Every streamed prefix of a reply that uses every construct must parse
/// without dropping a word — the island re-renders on each chunk.
#[test]
fn every_streaming_prefix_keeps_all_words() {
    let reply = r#"## Summary
Fixed the **login** bug in `auth.ts` — see [docs](https://example.dev/auth).

1. Reproduced locally
   - token refresh skipped expiry
2. Patched:
   ```swift
   guard token.isValid else { return }
   ```
- [x] unit tests
- [ ] manual check

| File | Lines | Status |
|:-----|------:|:------:|
| auth.ts | 12 | done |
| session.ts | 4 | `a | b` |

> **Note** restart the server
continued note

---
Setext Title
===
~~~
trailing unclosed fence
"#;
    let total = reply.chars().count();
    for end in 0..=total {
        let prefix: String = reply.chars().take(end).collect();
        assert!(
            words(&prefix).is_subset(&words_of_blocks(&parse(&prefix))),
            "lost words at prefix length {end}"
        );
    }
}

#[test]
fn randomised_input_never_loses_words() {
    let fragments = [
        "# head",
        "## sub ##",
        "para text",
        "- item",
        "  - child",
        "1. first",
        "3) third",
        "- [ ] task",
        "- [x] done",
        "```js",
        "```",
        "~~~",
        "| c1 | c2 |",
        "|---|:-:|",
        "| v1 | v2 |",
        "> quote",
        ">> deeper",
        "---",
        "***",
        "",
        "   ",
        "\tindented",
        "===",
        "trailing words",
        "`code | span`",
    ];
    let mut generator = SeededGenerator::new(0xC0DE);
    for _ in 0..400 {
        let count = 1 + generator.below(18);
        let text = (0..count)
            .map(|_| fragments[generator.below(fragments.len())])
            .collect::<Vec<_>>()
            .join("\n");
        assert!(
            words(&text).is_subset(&words_of_blocks(&parse(&text))),
            "lost words in:\n{text}"
        );
    }
}

#[test]
fn parsing_a_large_reply_stays_fast() {
    let chunk = r#"### Step
Some **explanation** with `code` and a [link](https://example.dev).
- item one
  - nested item
- [x] task
| a | b |
|---|--:|
| 1 | 2 |
```swift
let value = compute()
```

"#;
    let reply = chunk.repeat(400); // ~70 KB
    let start = Instant::now();
    let blocks = parse(&reply);
    let elapsed_ms = start.elapsed().as_secs_f64() * 1000.0;
    assert_eq!(
        blocks
            .iter()
            .filter(|block| matches!(block, MarkdownBlock::Table(_)))
            .count(),
        400
    );
    assert!(elapsed_ms < 3_000.0, "took {elapsed_ms} ms");
}

// MARK: - Helpers

/// Words of two or more letters/digits that aren't pure numbers: list
/// ordinals and the `x` of a checkbox legitimately move into structure.
fn words(text: &str) -> HashSet<String> {
    text.split(|c: char| !c.is_alphanumeric())
        .filter(|word| word.chars().count() > 1 && !word.chars().all(|c| c.is_numeric()))
        .map(str::to_owned)
        .collect()
}

fn words_of_blocks(blocks: &[MarkdownBlock]) -> HashSet<String> {
    words(&all_text(blocks))
}

fn all_text(blocks: &[MarkdownBlock]) -> String {
    blocks
        .iter()
        .map(|block| match block {
            MarkdownBlock::Heading { text, .. } | MarkdownBlock::Paragraph(text) => text.clone(),
            MarkdownBlock::List(list) => list
                .items
                .iter()
                .map(|item| all_text(&item.blocks))
                .collect::<Vec<_>>()
                .join(" "),
            MarkdownBlock::Code(code) => {
                format!(
                    "{} {}",
                    code.language.clone().unwrap_or_default(),
                    code.code
                )
            }
            MarkdownBlock::Table(table) => table
                .header
                .iter()
                .cloned()
                .chain(table.rows.iter().flatten().cloned())
                .collect::<Vec<_>>()
                .join(" "),
            MarkdownBlock::Quote(inner) => all_text(inner),
            MarkdownBlock::ThematicBreak => String::new(),
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn max_depth(blocks: &[MarkdownBlock]) -> usize {
    blocks
        .iter()
        .map(|block| match block {
            MarkdownBlock::List(list) => {
                1 + list
                    .items
                    .iter()
                    .map(|item| max_depth(&item.blocks))
                    .max()
                    .unwrap_or(0)
            }
            MarkdownBlock::Quote(inner) => 1 + max_depth(inner),
            _ => 0,
        })
        .max()
        .unwrap_or(0)
}

/// The test suite's `SeededGenerator`: deterministic xorshift, so the
/// randomised test replays identically.
struct SeededGenerator {
    state: u64,
}

impl SeededGenerator {
    fn new(seed: u64) -> Self {
        Self { state: seed }
    }

    fn next(&mut self) -> u64 {
        self.state ^= self.state << 13;
        self.state ^= self.state >> 7;
        self.state ^= self.state << 17;
        self.state
    }

    /// `Int.random(in: 0..<upperBound)` with the suite's generator.
    fn below(&mut self, upper_bound: usize) -> usize {
        (self.next() % upper_bound as u64) as usize
    }
}
