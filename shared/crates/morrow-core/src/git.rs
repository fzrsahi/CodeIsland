//! The checked-out branch of a session's `cwd` (`GitBranchReader`,
//! `macos/Sources/MorrowCore/GitBranchReader.swift`), read from the `.git` metadata
//! rather than by spawning `git`: sessions fire hooks many times a minute and
//! a sandboxed `cwd` makes subprocesses costly.
//!
//! `morrow-core` opens nothing, so the disk arrives as a [`Disk`]: the shell
//! implements it with `std::fs` and passes it in. Paths go through
//! [`Path`]/[`PathBuf`] — joined and split by segment, never by pasting a
//! `"/"` — so the same walk yields `\` separators on Windows.
//!
//! Unicode: Swift compares `Character`s (grapheme clusters), this compares
//! `char`s (scalar values).

use std::path::{Component, Path, PathBuf};

/// How deep the walk climbs before giving up, so a bogus `cwd` never scans
/// the whole filesystem upward.
const MAX_DEPTH: usize = 12;

/// Checked-out branch info for a session's `cwd`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GitBranchInfo {
    pub branch: String,
    /// The checkout is a linked worktree (`.git/worktrees/<name>`), not the
    /// repository's primary checkout and not a submodule.
    pub is_worktree: bool,
}

/// What the disk shows at one path: `FileManager.fileExists(atPath:isDirectory:)`
/// plus, for a file, `String(contentsOfFile:encoding:)`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum DiskEntry {
    Directory,
    File(String),
}

/// The disk the walk reads. `None` is "nothing there".
pub trait Disk {
    fn entry(&self, path: &Path) -> Option<DiskEntry>;
}

/// `GitBranchReader.read(cwd:)`: walk up from `cwd` to the nearest `.git`
/// entry — a directory for a primary checkout, a `gitdir:` pointer file for
/// linked worktrees and submodules — and resolve HEAD.
pub fn read<D: Disk + ?Sized>(cwd: &str, disk: &D) -> Option<GitBranchInfo> {
    let mut dir = standardize(Path::new(cwd));
    for _ in 0..MAX_DEPTH {
        let git_path = dir.join(".git");
        match disk.entry(&git_path) {
            Some(DiskEntry::Directory) => return head_info(&git_path, false, disk),
            Some(DiskEntry::File(pointer)) => {
                let git_dir = parse_gitdir_pointer(&pointer, &dir)?;
                // Linked worktrees resolve to <repo>/.git/worktrees/<name>.
                // Submodules are also gitdir-pointer checkouts but resolve
                // to .git/modules/… — and a repo merely *located under* a
                // directory named "worktrees" must not match either.
                let is_worktree = is_linked_worktree(&git_dir);
                return head_info(&git_dir, is_worktree, disk);
            }
            None => {}
        }
        dir = match dir.parent() {
            Some(parent) if !parent.as_os_str().is_empty() => parent.to_path_buf(),
            _ => return None,
        };
    }
    None
}

fn head_info<D: Disk + ?Sized>(
    git_dir: &Path,
    is_worktree: bool,
    disk: &D,
) -> Option<GitBranchInfo> {
    let Some(DiskEntry::File(head)) = disk.entry(&git_dir.join("HEAD")) else {
        return None;
    };
    let branch = parse_head(&head)?;
    Some(GitBranchInfo {
        branch,
        is_worktree,
    })
}

/// "ref: refs/heads/<branch>" → branch name; a detached 40-hex HEAD → its
/// 7-character short SHA.
pub fn parse_head(content: &str) -> Option<String> {
    let line = content.trim();
    if line.is_empty() {
        return None;
    }
    if let Some(reference) = line.strip_prefix("ref: ") {
        let branch = reference.strip_prefix("refs/heads/").unwrap_or(reference);
        return (!branch.is_empty()).then(|| branch.to_owned());
    }
    if line.chars().count() >= 7 && line.chars().all(|c| c.is_ascii_hexdigit()) {
        return Some(line.chars().take(7).collect());
    }
    None
}

/// The `.git` pointer file's body: "gitdir: <absolute-or-relative path>".
pub fn parse_gitdir_pointer(content: &str, relative_to: &Path) -> Option<PathBuf> {
    let line = content.trim();
    let path = line
        .strip_prefix("gitdir:")?
        .trim_matches(|c| c == ' ' || c == '\t');
    if path.is_empty() {
        return None;
    }
    let path = Path::new(path);
    let path = if path.is_absolute() {
        path.to_path_buf()
    } else {
        relative_to.join(path)
    };
    Some(standardize(&path))
}

/// `.` and `..` resolved lexically, repeated and trailing separators dropped;
/// symlinks are not followed, as `NSString.standardizingPath` does not.
pub fn standardize(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for component in path.components() {
        match component {
            Component::CurDir => {}
            Component::ParentDir => {
                if !out.pop() {
                    out.push("..");
                }
            }
            other => out.push(other.as_os_str()),
        }
    }
    out
}

/// Whether `git_dir` sits at `<repo>/.git/worktrees/<name>` — by segments, so
/// a checkout inside a directory literally named "worktrees" or a submodule
/// (`.git/modules/…`) is not one.
fn is_linked_worktree(git_dir: &Path) -> bool {
    let names: Vec<&str> = git_dir
        .components()
        .filter_map(|component| match component {
            Component::Normal(name) => name.to_str(),
            _ => None,
        })
        .collect();
    names
        .windows(2)
        .any(|pair| pair[0] == ".git" && pair[1] == "worktrees")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn worktrees_are_found_by_segment() {
        assert!(is_linked_worktree(Path::new("/repo/.git/worktrees/fix-1")));
        assert!(!is_linked_worktree(Path::new(
            "/w/worktrees/repo/.git/modules/sub"
        )));
        assert!(!is_linked_worktree(Path::new("/repo/.git")));
    }

    #[test]
    fn standardized_paths_are_lexical() {
        assert_eq!(
            standardize(Path::new("/a/./b/../c//d/")),
            PathBuf::from("/a/c/d")
        );
        assert_eq!(standardize(Path::new("/a/b/../..")), PathBuf::from("/"));
    }
}
