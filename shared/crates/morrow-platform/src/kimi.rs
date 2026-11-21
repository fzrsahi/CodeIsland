//! Kimi Code CLI's hooks on this machine: `~/.kimi-code/config.toml`, or the
//! legacy `~/.kimi/config.toml` when that is what the user has
//! (`installKimiHooks`, `kimiHome`).
//!
//! Kimi is only touched when one of its directories exists: a `config.toml`
//! for a CLI nobody runs is clutter, and the Swift installer makes the same
//! choice.

use std::fs;
use std::path::{Path, PathBuf};

use morrow_core::installer::claude_hooks::HOOK_COMMAND;
use morrow_core::installer::kimi;

use crate::hooks::{Error, back_up, read_text};

/// Where Kimi's config is.
pub struct Site {
    pub config_dir: PathBuf,
    pub config: PathBuf,
}

impl Site {
    /// `~/.kimi-code` when present, else `~/.kimi`, else the modern path (for
    /// display, and for what a future install would use).
    pub fn new(home: &Path) -> Self {
        let modern = home.join(".kimi-code");
        let legacy = home.join(".kimi");
        let config_dir = if modern.is_dir() {
            modern
        } else if legacy.is_dir() {
            legacy
        } else {
            modern
        };
        Self {
            config: config_dir.join("config.toml"),
            config_dir,
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
    pub installed: bool,
    pub config: PathBuf,
}

pub fn status(site: &Site) -> Status {
    Status {
        detected: site.detected(),
        installed: read_text(&site.config)
            .ok()
            .flatten()
            .is_some_and(|text| kimi::is_installed(&text)),
        config: site.config.clone(),
    }
}

/// Install or repair. `None` when Kimi is not on this machine.
pub fn install(site: &Site, stamp: &str) -> Result<Option<()>, Error> {
    if !site.detected() {
        return Ok(None);
    }
    let existing = read_text(&site.config)?.unwrap_or_default();
    let text = kimi::install(&existing, HOOK_COMMAND);
    if text == existing {
        return Ok(Some(()));
    }
    if let Some(parent) = site.config.parent() {
        fs::create_dir_all(parent)?;
    }
    // A file that is not there yet has nothing to back up.
    if site.config.is_file() {
        back_up(&site.config, stamp)?;
    }
    fs::write(&site.config, text)?;
    Ok(Some(()))
}

/// Take our blocks out. `None` when Kimi is not on this machine.
pub fn uninstall(site: &Site, stamp: &str) -> Result<Option<()>, Error> {
    if !site.detected() {
        return Ok(None);
    }
    let Some(existing) = read_text(&site.config)? else {
        return Ok(Some(()));
    };
    let text = kimi::remove(&existing);
    if text == existing {
        return Ok(Some(()));
    }
    back_up(&site.config, stamp)?;
    fs::write(&site.config, text)?;
    Ok(Some(()))
}
