//! The music card's adapters with a scripted runner (#102): no player, no
//! audio hardware, and every command still checked.

use std::cell::RefCell;
use std::collections::BTreeMap;

use morrow_core::music::{Position, Status};
use morrow_platform::music::{NowPlaying, Runner, SystemVolume, lyrics};

/// Answers commands from a table and remembers what it was asked.
struct Fake {
    answers: BTreeMap<String, Result<String, String>>,
    asked: RefCell<Vec<String>>,
}

impl Fake {
    fn new(answers: &[(&str, &str)]) -> Self {
        Self {
            answers: answers
                .iter()
                .map(|(command, output)| ((*command).to_owned(), Ok((*output).to_owned())))
                .collect(),
            asked: RefCell::new(Vec::new()),
        }
    }

    fn with_error(mut self, command: &str, error: &str) -> Self {
        self.answers
            .insert(command.to_owned(), Err(error.to_owned()));
        self
    }

    fn asked(&self) -> Vec<String> {
        self.asked.borrow().clone()
    }
}

impl Runner for Fake {
    fn run(&self, program: &str, args: &[&str]) -> Result<String, String> {
        let command = format!("{program} {}", args.join(" "));
        self.asked.borrow_mut().push(command.clone());
        match self.answers.get(&command) {
            Some(answer) => answer.clone(),
            None => Err(format!("{program}: not scripted ({command})")),
        }
    }
}

const METADATA: &str = "spotify\tPlaying\tBoards of Canada\tRoygbiv\tMusic Has the Right…\t240000000\t61000000\tspotify:track:1\n";

fn playerctl_metadata_command() -> String {
    format!(
        "playerctl metadata --format {}",
        morrow_core::music::METADATA_FORMAT
    )
}

#[test]
fn a_playing_track_comes_back_with_its_position() {
    let fake = Fake::new(&[
        (playerctl_metadata_command().as_str(), METADATA),
        ("playerctl status --format {{canSeek}}", "true"),
        ("playerctl status --format {{canGoNext}}", "true"),
        ("playerctl status --format {{canGoPrevious}}", "false"),
    ]);
    let adapter = NowPlaying::new(&fake, 1_000);
    let track = adapter.track().expect("no error").expect("a track");

    assert_eq!(track.title, "Roygbiv");
    assert_eq!(track.artist, "Boards of Canada");
    assert_eq!(track.status, Status::Playing);
    assert!(track.can_seek, "seek is offered by this player");
    assert!(track.can_go_next);
    assert!(!track.can_go_previous);

    // The card ticks: two seconds on, two seconds further in.
    let position: Position = adapter.position(&track);
    assert_eq!(position.at(3_000), 63_000_000);
}

#[test]
fn no_player_is_an_empty_card_not_an_error() {
    let fake =
        Fake::new(&[]).with_error(&playerctl_metadata_command(), "playerctl: No players found");
    let adapter = NowPlaying::new(&fake, 0);
    assert_eq!(adapter.track().expect("not an error"), None);
}

#[test]
fn a_player_that_cannot_seek_says_so() {
    let fake = Fake::new(&[
        (
            playerctl_metadata_command().as_str(),
            "mpv\tPaused\tA\tT\t\t\t\t",
        ),
        ("playerctl status --format {{canSeek}}", "false"),
    ]);
    let track = NowPlaying::new(&fake, 0)
        .track()
        .expect("ok")
        .expect("a track");
    assert!(!track.can_seek, "the card hides the seek control");
    assert_eq!(track.status, Status::Paused);
    assert_eq!(track.length_us, None, "no progress bar without a length");
}

#[test]
fn a_position_is_read_when_the_metadata_omits_it() {
    let fake = Fake::new(&[
        (
            playerctl_metadata_command().as_str(),
            "spotify\tPlaying\tA\tT\t\t240000000\t\t",
        ),
        ("playerctl position", "42.5\n"),
        ("playerctl status --format {{canSeek}}", "true"),
    ]);
    let track = NowPlaying::new(&fake, 0)
        .track()
        .expect("ok")
        .expect("track");
    assert_eq!(track.position_us, 42_500_000);
}

#[test]
fn the_controls_run_the_commands_playerctl_documents() {
    let fake = Fake::new(&[
        ("playerctl play-pause", ""),
        ("playerctl next", ""),
        ("playerctl previous", ""),
        ("playerctl position 10+", ""),
        ("playerctl position 10-", ""),
    ]);
    let adapter = NowPlaying::new(&fake, 0);
    adapter.play_pause().expect("play-pause");
    adapter.next().expect("next");
    adapter.previous().expect("previous");
    adapter.seek_by(10_000_000).expect("forward");
    adapter.seek_by(-10_000_000).expect("back");

    assert_eq!(
        fake.asked(),
        vec![
            "playerctl play-pause",
            "playerctl next",
            "playerctl previous",
            "playerctl position 10+",
            "playerctl position 10-",
        ]
    );
}

// MARK: - Volume

#[test]
fn volume_prefers_wpctl_and_sets_with_the_same_tool() {
    let fake = Fake::new(&[
        ("wpctl get-volume @DEFAULT_AUDIO_SINK@", "Volume: 0.42\n"),
        ("wpctl set-volume @DEFAULT_AUDIO_SINK@ 60%", ""),
        ("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle", ""),
    ]);
    let mut volume = SystemVolume::new(&fake);
    let reading = volume.read().expect("a reading");
    assert_eq!(reading.percent, 42);
    assert!(!reading.muted);

    volume.set_percent(60).expect("set");
    volume.toggle_mute().expect("mute");
    assert!(
        fake.asked()
            .iter()
            .all(|command| command.starts_with("wpctl "))
    );
}

#[test]
fn without_pipewire_pactl_answers() {
    let fake = Fake::new(&[
        (
            "pactl get-sink-volume @DEFAULT_SINK@",
            "Volume: front-left: 27525 /  42% / -22.78 dB\n",
        ),
        ("pactl get-sink-mute @DEFAULT_SINK@", "Mute: yes\n"),
        ("pactl set-sink-volume @DEFAULT_SINK@ 80%", ""),
    ]);
    let mut volume = SystemVolume::new(&fake);
    let reading = volume.read().expect("a reading");
    assert_eq!(reading.percent, 42);
    assert!(reading.muted);

    volume.set_percent(80).expect("set");
    assert!(
        fake.asked()
            .last()
            .is_some_and(|command| command.starts_with("pactl set-sink-volume"))
    );
}

#[test]
fn volume_above_a_hundred_is_capped_when_written() {
    let fake = Fake::new(&[
        ("wpctl get-volume @DEFAULT_AUDIO_SINK@", "Volume: 0.30\n"),
        ("wpctl set-volume @DEFAULT_AUDIO_SINK@ 150%", ""),
    ]);
    let mut volume = SystemVolume::new(&fake);
    volume.read().expect("a reading");
    volume.set_percent(200).expect("set");
    assert_eq!(
        fake.asked().last().map(String::as_str),
        Some("wpctl set-volume @DEFAULT_AUDIO_SINK@ 150%")
    );
}

// MARK: - Lyrics

fn track() -> morrow_core::music::Track {
    morrow_core::music::Track {
        artist: "Boards of Canada".into(),
        title: "Roygbiv".into(),
        length_us: Some(240_000_000),
        ..Default::default()
    }
}

#[test]
fn lyrics_come_from_lrclib_and_are_parsed() {
    let body = r#"{"syncedLyrics":"[00:12.34] The first line\n[00:15.50] Second\n"}"#;
    let fake = Fake::new(&[(
        "curl -fsS --max-time 4 -G https://lrclib.net/api/get --data-urlencode artist_name=Boards of Canada --data-urlencode track_name=Roygbiv --data-urlencode duration=240",
        body,
    )]);
    let lines = lyrics(&fake, &track()).expect("ok").expect("lyrics");
    assert_eq!(lines.len(), 2);
    assert_eq!(lines[0].at_ms, 12_340);
    assert_eq!(lines[1].text, "Second");
}

#[test]
fn no_lyrics_is_not_an_error() {
    // 404 → curl `-f` exits 22.
    let fake = Fake::new(&[]).with_error(
        "curl -fsS --max-time 4 -G https://lrclib.net/api/get --data-urlencode artist_name=Boards of Canada --data-urlencode track_name=Roygbiv --data-urlencode duration=240",
        "curl exited 22",
    );
    assert_eq!(lyrics(&fake, &track()).expect("no error"), None);

    // A plain answer without synced lyrics is empty too.
    let plain = Fake::new(&[(
        "curl -fsS --max-time 4 -G https://lrclib.net/api/get --data-urlencode artist_name=Boards of Canada --data-urlencode track_name=Roygbiv --data-urlencode duration=240",
        r#"{"plainLyrics":"no stamps"}"#,
    )]);
    assert_eq!(lyrics(&plain, &track()).expect("no error"), None);
}

#[test]
fn a_track_without_artist_or_title_asks_nothing() {
    let fake = Fake::new(&[]);
    let empty = morrow_core::music::Track::default();
    assert_eq!(lyrics(&fake, &empty).expect("no error"), None);
    assert!(fake.asked().is_empty(), "no request for an empty title");
}
