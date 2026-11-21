//! The user's Morrow settings: one JSON object at
//! `~/.codeisland/settings.json`, edited with the same minimal-diff writer the
//! installers use, so a hand-edit with comments survives a toggle in the UI.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use morrow_core::installer::json_editor::set_top_level_value;
use morrow_core::installer::settings as document;
use serde_json::Value;

/// Where the file is.
pub fn path(codeisland_dir: &Path) -> PathBuf {
    codeisland_dir.join("settings.json")
}

/// Read the document. A file that is absent is an empty object; a file that
/// does not parse is an error, never a rewrite (`#89`).
pub fn load(codeisland_dir: &Path) -> io::Result<Value> {
    let path = path(codeisland_dir);
    match fs::read_to_string(&path) {
        Ok(text) => Ok(Value::Object(document::object(&text).unwrap_or_default())),
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            Ok(Value::Object(Default::default()))
        }
        Err(error) => Err(error),
    }
}

/// Set one top-level key, leaving every other byte alone. Returns whether the
/// file changed.
pub fn set(codeisland_dir: &Path, key: &str, value: &Value) -> io::Result<bool> {
    let path = path(codeisland_dir);
    let existing = fs::read_to_string(&path).ok();
    let merged = match existing.as_deref() {
        Some(text) => set_top_level_value(text, key, value).ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::InvalidData,
                format!("{} is not a JSON object; leaving it alone", path.display()),
            )
        })?,
        None => {
            let mut map = serde_json::Map::new();
            map.insert(key.to_owned(), value.clone());
            let mut text =
                serde_json::to_string_pretty(&Value::Object(map)).map_err(io::Error::other)?;
            text.push('\n');
            text
        }
    };
    if existing.as_deref() == Some(merged.as_str()) {
        return Ok(false);
    }
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(&path, merged)?;
    Ok(true)
}
