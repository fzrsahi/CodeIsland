//! OpenCode's plugin install (`installOpencodePlugin` / `uninstallOpencodePlugin`).
//!
//! OpenCode has no hooks key: it loads what `opencode.json(c)` lists under
//! `plugin`, and the plugin itself is a file we write. So this does three
//! things — drop the JS where OpenCode reads it, register that path in the
//! user's config, and take both back out on uninstall — while never creating
//! `~/.config/opencode` for someone who does not use it.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use morrow_core::installer::opencode;

use crate::hooks::{Error, back_up, read_text};

/// The plugin as macOS ships it. One file, so the two cores cannot drift — the
/// path is into the shared tree, and #118's layout change moves it once.
pub const PLUGIN_SOURCE: &str =
    include_str!("../../../../Sources/Morrow/Resources/morrow-opencode.js");

/// Bumped when the plugin changes: an older copy on disk is rewritten
/// (`opencodePluginVersion`).
pub const PLUGIN_VERSION: &str = "v11";

/// Where OpenCode keeps everything, and which of its config files exists.
pub struct Site {
    pub config_dir: PathBuf,
    pub plugin: PathBuf,
    /// `opencode.jsonc` when the user has one, else `opencode.json`.
    pub config: PathBuf,
    /// `config.json`, the name older OpenCode used: our reference is cleaned
    /// out of it so the plugin never loads twice.
    pub legacy_config: PathBuf,
}

impl Site {
    pub fn new(home: &Path) -> Self {
        let config_dir = home.join(".config/opencode");
        let jsonc = config_dir.join("opencode.jsonc");
        let config = if jsonc.is_file() {
            jsonc
        } else {
            config_dir.join("opencode.json")
        };
        Self {
            plugin: config_dir.join("plugins/codeisland.js"),
            legacy_config: config_dir.join("config.json"),
            config_dir,
            config,
        }
    }

    pub fn detected(&self) -> bool {
        self.config_dir.is_dir()
    }
}

/// What the card shows.
#[derive(Debug, PartialEq, Eq, serde::Serialize)]
pub struct Status {
    pub detected: bool,
    /// The plugin file is there and carries this build's version marker.
    pub plugin_installed: bool,
    /// `opencode.json(c)` names it.
    pub registered: bool,
    pub config: PathBuf,
}

pub fn status(site: &Site) -> Status {
    let detected = site.detected();
    let plugin_installed = read_text(&site.plugin)
        .ok()
        .flatten()
        .is_some_and(|text| text.contains(&version_marker()));
    let registered = read_text(&site.config)
        .ok()
        .flatten()
        .is_some_and(|text| opencode::is_registered(&text));
    Status {
        detected,
        plugin_installed,
        registered,
        config: site.config.clone(),
    }
}

/// Install or repair. `None` when OpenCode is not on this machine, or when its
/// config does not parse (the plugin file is not staged then either — a file
/// nobody reads is worse than none).
pub fn install(site: &Site, stamp: &str) -> Result<Option<()>, Error> {
    if !site.detected() {
        return Ok(None);
    }
    let existing = read_text(&site.config)?;
    let plugin_ref = format!("file://{}", site.plugin.display());
    let merged = opencode::merge_plugin_ref(existing.as_deref(), &plugin_ref)
        .ok_or_else(|| Error::UnparseableSettings(site.config.clone()))?;

    // The plugin first: a config naming a file that is not there is a broken
    // startup, the other way round is merely dormant.
    if let Some(parent) = site.plugin.parent() {
        fs::create_dir_all(parent)?;
    }
    let plugin_source = payload();
    if read_text(&site.plugin)?.as_deref() != Some(plugin_source.as_str()) {
        fs::write(&site.plugin, &plugin_source)?;
    }

    if existing.as_deref() != Some(merged.as_str()) {
        if existing.is_some() {
            back_up(&site.config, stamp)?;
        }
        fs::write(&site.config, &merged)?;
    }

    // A `config.json` registration from an older build would load us twice.
    if let Some(legacy) = read_text(&site.legacy_config)? {
        if let Some(cleaned) = opencode::remove_plugin_ref(&legacy) {
            back_up(&site.legacy_config, stamp)?;
            fs::write(&site.legacy_config, cleaned)?;
        }
    }
    Ok(Some(()))
}

/// Take both back out. `None` when OpenCode is not on this machine.
pub fn uninstall(site: &Site, stamp: &str) -> Result<Option<()>, Error> {
    if !site.detected() {
        return Ok(None);
    }
    for config in [&site.config, &site.legacy_config] {
        let Some(existing) = read_text(config)? else {
            continue;
        };
        if let Some(cleaned) = opencode::remove_plugin_ref(&existing) {
            back_up(config, stamp)?;
            fs::write(config, cleaned)?;
        }
    }
    match fs::remove_file(&site.plugin) {
        Ok(()) => {}
        Err(error) if error.kind() == io::ErrorKind::NotFound => {}
        Err(error) => return Err(Error::Io(error)),
    }
    Ok(Some(()))
}

/// The plugin text as it lands on disk: the shipped file, whose version line
/// already carries the marker.
fn payload() -> String {
    PLUGIN_SOURCE.to_owned()
}

fn version_marker() -> String {
    format!("// version: {PLUGIN_VERSION}")
}
