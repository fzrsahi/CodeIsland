//! The music card's readings (#102): metadata as `playerctl` prints it, a
//! position that keeps moving, LRC lyrics and the two volume tools.

use morrow_core::music::{
    METADATA_FORMAT, Position, Status, Track, Volume, lyrics_at, parse_flag, parse_lrc,
    parse_metadata, parse_pactl_volume, parse_wpctl_volume,
};

// MARK: - Metadata

#[test]
fn metadata_parses_every_field_playerctl_prints() {
    let line = "spotify\tPlaying\tBoards of Canada\tRoygbiv\tMusic Has the Right…\t240123456\t61000000\tspotify:track:1\n";
    let track = parse_metadata(line);
    assert_eq!(track.player, "spotify");
    assert_eq!(track.status, Status::Playing);
    assert_eq!(track.artist, "Boards of Canada");
    assert_eq!(track.title, "Roygbiv");
    assert_eq!(track.album, "Music Has the Right…");
    assert_eq!(track.length_us, Some(240_123_456));
    assert_eq!(track.position_us, 61_000_000);
}

#[test]
fn a_player_that_omits_fields_is_not_an_error() {
    let track = parse_metadata("mpv\tPaused\tArtist\tTitle\t\t\t\t");
    assert_eq!(track.status, Status::Paused);
    assert_eq!(track.length_us, None, "no length, no progress bar");
    assert_eq!(track.position_us, 0);

    let empty = parse_metadata("");
    assert_eq!(empty.status, Status::Stopped);
    assert_eq!(empty.title, "");
}

#[test]
fn the_format_names_the_fields_the_parser_reads() {
    for field in [
        "playerName",
        "status",
        "artist",
        "title",
        "album",
        "mpris:length",
        "position",
    ] {
        assert!(METADATA_FORMAT.contains(field), "{field} missing");
    }
}

#[test]
fn can_flags_are_plain_booleans() {
    assert!(parse_flag("true"));
    assert!(parse_flag(" TRUE\n"));
    assert!(!parse_flag("false"));
    assert!(!parse_flag(""));
}

// MARK: - Position

#[test]
fn a_playing_track_advances_between_readings() {
    // Read 61 s at t=1000 ms; two seconds later the card shows 63 s even
    // though the player never announced a position change.
    let position = Position::new(61_000_000, 1_000, Status::Playing, Some(240_123_456));
    assert_eq!(position.at(1_000), 61_000_000);
    assert_eq!(position.at(3_000), 63_000_000);
    assert!(position.progress(3_000).unwrap() > 0.26);
}

#[test]
fn a_paused_track_does_not_move() {
    let position = Position::new(61_000_000, 1_000, Status::Paused, Some(240_123_456));
    assert_eq!(position.at(60_000), 61_000_000, "paused stays put");
}

#[test]
fn the_position_stops_at_the_end_of_the_track() {
    let position = Position::new(239_500_000, 0, Status::Playing, Some(240_000_000));
    assert_eq!(position.at(10_000), 240_000_000, "clamped, not overrun");
    assert_eq!(position.progress(10_000), Some(1.0));
}

#[test]
fn a_reading_from_the_future_does_not_run_backwards() {
    let position = Position::new(5_000_000, 9_000, Status::Playing, None);
    assert_eq!(position.at(1_000), 5_000_000, "clock skew is ignored");
    assert_eq!(position.progress(1_000), None, "no length, no progress");
}

#[test]
fn a_looping_track_is_corrected_by_the_next_real_reading() {
    let position = Position::new(239_000_000, 0, Status::Playing, Some(240_000_000));
    assert_eq!(position.at(5_000), 240_000_000);
    // The player reports 1 s after looping: a new Position starts over.
    let looped = Position::new(1_000_000, 6_000, Status::Playing, Some(240_000_000));
    assert_eq!(looped.at(6_000), 1_000_000);
}

// MARK: - Lyrics

#[test]
fn lrc_lyrics_parse_with_their_timestamps() {
    let source = "[ar:Boards of Canada]\n[ti:Roygbiv]\n[00:12.34] The first line\n[00:15.5]Second line\n[01:02.345] Third\n";
    let lines = parse_lrc(source);
    assert_eq!(lines.len(), 3, "metadata rows are not lyrics");
    assert_eq!(lines[0].at_ms, 12_340);
    assert_eq!(lines[0].text, "The first line");
    assert_eq!(lines[1].at_ms, 15_500);
    assert_eq!(lines[2].at_ms, 62_345);
}

#[test]
fn several_stamps_on_one_line_repeat_the_text() {
    let lines = parse_lrc("[00:01.00][00:31.00] chorus\n");
    assert_eq!(lines.len(), 2);
    assert_eq!(lines[0].text, "chorus");
    assert_eq!(lines[1].at_ms, 31_000);
}

#[test]
fn the_lines_are_sorted_even_when_the_file_is_not() {
    let lines = parse_lrc("[00:20.00] late\n[00:10.00] early\n");
    assert_eq!(lines[0].text, "early");
    assert_eq!(lines[1].text, "late");
}

#[test]
fn the_current_line_and_the_next_one() {
    let lines = parse_lrc("[00:00.00] one\n[00:05.00] two\n[00:10.00] three\n");
    let (current, next) = lyrics_at(&lines, 6_000);
    assert_eq!(current.map(|line| line.text.as_str()), Some("two"));
    assert_eq!(next.map(|line| line.text.as_str()), Some("three"));

    let (before, first) = lyrics_at(&lines, 0);
    assert!(before.is_none() || before.map(|l| l.text.as_str()) == Some("one"));
    assert_eq!(
        first.map(|line| line.text.as_str()),
        Some("two").or(Some("two"))
    );

    let (last, after) = lyrics_at(&lines, 60_000);
    assert_eq!(last.map(|line| line.text.as_str()), Some("three"));
    assert!(after.is_none());
}

#[test]
fn a_track_without_lyrics_is_empty_not_wrong() {
    assert!(parse_lrc("").is_empty());
    assert!(parse_lrc("just prose, no stamps\n").is_empty());
    let (current, next) = lyrics_at(&[], 1_000);
    assert!(current.is_none() && next.is_none());
}

// MARK: - Volume

#[test]
fn wpctl_volume_reads_scalar_and_mute() {
    assert_eq!(
        parse_wpctl_volume("Volume: 0.42\n"),
        Some(Volume {
            percent: 42,
            muted: false
        })
    );
    assert_eq!(
        parse_wpctl_volume("Volume: 1.00 [MUTED]\n"),
        Some(Volume {
            percent: 100,
            muted: true
        })
    );
    assert_eq!(parse_wpctl_volume("no volume here\n"), None);
}

#[test]
fn pactl_volume_reads_the_first_percentage_and_the_mute_line() {
    let volume =
        "Volume: front-left: 27525 /  42% / -22.78 dB,   front-right: 27525 /  42% / -22.78 dB\n";
    assert_eq!(
        parse_pactl_volume(volume, "Mute: no\n"),
        Some(Volume {
            percent: 42,
            muted: false
        })
    );
    assert_eq!(
        parse_pactl_volume(volume, "Mute: yes\n").map(|volume| volume.muted),
        Some(true)
    );
    assert_eq!(parse_pactl_volume("nothing\n", "Mute: no\n"), None);
}

#[test]
fn a_track_struct_is_what_the_card_gets() {
    let track = Track::default();
    assert_eq!(track.status, Status::Stopped);
    assert!(!track.can_seek);
}
