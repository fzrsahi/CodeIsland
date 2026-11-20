//! The YAML sources on this machine (`~/.hermes/config.yaml`,
//! `~/.trae/traecli.yaml`), installed as a managed block (#151).
//!
//! Same rules as everywhere else in this crate: only a CLI that is here, a
//! back-up before the first write, nothing written when the text would not
//! change, and a file whose layout the core refuses is an error rather than a
//! guess.

use std::fs;
use std::path::{Path, PathBuf};

use morrow_core::installer::claude_hooks::HOOK_COMMAND;
use morrow_core::installer::yaml_hooks::{self as plan, Source};

use crate::hooks::{Error, back_up, read_text};

/// One YAML source, and where its file is.
pub struct Site {
    pub source: &'static Source,
    pub directory: PathBuf,
    pub config: PathBuf,
}

impl Site {
    pub fn new(home: &Path, source: &'static Source) -> Self {
        Self {
            directory: home.join(source.directory),
            config: home.join(source.path),
            source,
        }
    }

    pub fn detected(&self) -> bool {
        self.directory.is_dir()
    }
}

/// Every YAML source's site, in table order.
pub fn sites(home: &Path) -> Vec<Site> {
    plan::SOURCES
        .iter()
        .map(|source| Site::new(home, source))
        .collect()
}

/// What the card shows.
#[derive(Debug, PartialEq, Eq, serde::Serialize)]
pub struct Status {
    pub source: &'static str,
    pub name: &'static str,
    pub detected: bool,
    pub installed: bool,
    pub config: PathBuf,
    /// Why the file cannot be written, when it cannot.
    pub refusal: Option<String>,
}

pub fn status(site: &Site) -> Status {
    let existing = read_text(&site.config).ok().flatten();
    let installed = existing
        .as_deref()
        .is_some_and(|text| plan::is_installed(site.source, text));
    let refusal = match existing.as_deref() {
        Some(text) => plan::install(site.source, text, HOOK_COMMAND)
            .err()
            .map(|refusal| format!("{refusal:?}")),
        None => None,
    };
    Status {
        source: site.source.source,
        name: site.source.name,
        detected: site.detected(),
        installed,
        config: site.config.clone(),
        refusal,
    }
}

/// Install or repair. `None` when the CLI is not on this machine.
pub fn install(site: &Site, stamp: &str) -> Result<Option<()>, Error> {
    if !site.detected() {
        return Ok(None);
    }
    let existing = read_text(&site.config)?.unwrap_or_default();
    let text = plan::install(site.source, &existing, HOOK_COMMAND)
        .map_err(|refusal| Error::Refused(format!("{}: {refusal:?}", site.config.display())))?;
    if text == existing {
        return Ok(Some(()));
    }
    if let Some(parent) = site.config.parent() {
        fs::create_dir_all(parent)?;
    }
    if site.config.is_file() {
        back_up(&site.config, stamp)?;
    }
    fs::write(&site.config, text)?;
    Ok(Some(()))
}

/// Take our block out. `None` when the CLI is not on this machine.
pub fn uninstall(site: &Site, stamp: &str) -> Result<Option<()>, Error> {
    if !site.detected() {
        return Ok(None);
    }
    let Some(existing) = read_text(&site.config)? else {
        return Ok(Some(()));
    };
    let text = plan::remove(&existing);
    if text == existing {
        return Ok(Some(()));
    }
    back_up(&site.config, stamp)?;
    fs::write(&site.config, text)?;
    Ok(Some(()))
}
