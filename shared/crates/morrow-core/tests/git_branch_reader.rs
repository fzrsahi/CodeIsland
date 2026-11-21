//! `GitBranchReaderTests` (`macos/Tests/MorrowCoreTests/GitBranchReaderTests.swift`),
//! ported one test to one test. The Swift suite writes a temporary tree and
//! lets `FileManager` read it; morrow-core opens nothing, so the same tree is
//! an in-memory [`Disk`] handed to the walk.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use morrow_core::git::{DiskEntry, GitBranchInfo, parse_gitdir_pointer, parse_head, read};

/// The tree the walk sees: a path is a directory, a file with contents, or
/// nothing at all.
#[derive(Default)]
struct MemoryDisk {
    entries: BTreeMap<PathBuf, DiskEntry>,
}

impl MemoryDisk {
    fn dir(mut self, path: &str) -> Self {
        self.entries
            .insert(PathBuf::from(path), DiskEntry::Directory);
        self
    }

    fn file(mut self, path: &str, contents: &str) -> Self {
        self.entries
            .insert(PathBuf::from(path), DiskEntry::File(contents.to_owned()));
        self
    }

    fn head(self, git_dir: &str, contents: &str) -> Self {
        self.file(&format!("{git_dir}/HEAD"), contents)
    }
}

impl morrow_core::git::Disk for &MemoryDisk {
    fn entry(&self, path: &Path) -> Option<DiskEntry> {
        self.entries.get(path).cloned()
    }
}

fn info(branch: &str, is_worktree: bool) -> Option<GitBranchInfo> {
    Some(GitBranchInfo {
        branch: branch.to_owned(),
        is_worktree,
    })
}

const ROOT: &str = "/tmp/git-branch-tests";

fn read_from(disk: &MemoryDisk, cwd: &str) -> Option<GitBranchInfo> {
    read(cwd, &disk)
}

// MARK: - parseHEAD

#[test]
fn parse_head_branch_ref() {
    assert_eq!(
        parse_head("ref: refs/heads/main\n").as_deref(),
        Some("main")
    );
    assert_eq!(
        parse_head("ref: refs/heads/feat/notch-ui\n").as_deref(),
        Some("feat/notch-ui")
    );
}

#[test]
fn parse_head_detached_shortens_sha() {
    assert_eq!(
        parse_head("29e5256a1b2c3d4e5f60718293a4b5c6d7e8f901\n").as_deref(),
        Some("29e5256")
    );
}

#[test]
fn parse_head_rejects_garbage() {
    assert_eq!(parse_head(""), None);
    assert_eq!(parse_head("not a head"), None);
    assert_eq!(parse_head("ref: refs/heads/"), None);
}

// MARK: - parseGitdirPointer

#[test]
fn parse_gitdir_pointer_absolute_and_relative() {
    assert_eq!(
        parse_gitdir_pointer("gitdir: /repo/.git/worktrees/wt\n", Path::new("/x")),
        Some(PathBuf::from("/repo/.git/worktrees/wt"))
    );
    assert_eq!(
        parse_gitdir_pointer("gitdir: ../repo/.git\n", Path::new("/a/b")),
        Some(PathBuf::from("/a/repo/.git"))
    );
    assert_eq!(
        parse_gitdir_pointer("something else", Path::new("/a")),
        None
    );
}

// MARK: - read(cwd:)

#[test]
fn read_primary_checkout_from_subdirectory() {
    let disk = MemoryDisk::default()
        .dir(&format!("{ROOT}/repo/.git"))
        .head(&format!("{ROOT}/repo/.git"), "ref: refs/heads/main\n");
    assert_eq!(
        read_from(&disk, &format!("{ROOT}/repo/src/deep")),
        info("main", false)
    );
}

#[test]
fn read_linked_worktree() {
    let disk = MemoryDisk::default()
        .dir(&format!("{ROOT}/repo/.git"))
        .head(&format!("{ROOT}/repo/.git"), "ref: refs/heads/main\n")
        .dir(&format!("{ROOT}/repo/.git/worktrees/fix-1"))
        .head(
            &format!("{ROOT}/repo/.git/worktrees/fix-1"),
            "ref: refs/heads/fix/session-bug\n",
        )
        .file(
            &format!("{ROOT}/wt/.git"),
            &format!("gitdir: {ROOT}/repo/.git/worktrees/fix-1\n"),
        );
    assert_eq!(
        read_from(&disk, &format!("{ROOT}/wt")),
        info("fix/session-bug", true)
    );
}

#[test]
fn read_relative_gitdir_pointer() {
    let disk = MemoryDisk::default()
        .dir(&format!("{ROOT}/a/repo/.git/worktrees/wt"))
        .head(
            &format!("{ROOT}/a/repo/.git/worktrees/wt"),
            "ref: refs/heads/wt-branch\n",
        )
        .file(
            &format!("{ROOT}/a/b/wt/.git"),
            "gitdir: ../../repo/.git/worktrees/wt\n",
        );
    assert_eq!(
        read_from(&disk, &format!("{ROOT}/a/b/wt")),
        info("wt-branch", true)
    );
}

#[test]
fn read_detached_head() {
    let disk = MemoryDisk::default()
        .dir(&format!("{ROOT}/repo/.git"))
        .head(
            &format!("{ROOT}/repo/.git"),
            "0123456789abcdef0123456789abcdef01234567\n",
        );
    assert_eq!(
        read_from(&disk, &format!("{ROOT}/repo")),
        info("0123456", false)
    );
}

#[test]
fn read_non_repo_returns_nothing() {
    let disk = MemoryDisk::default().file(&format!("{ROOT}/plain/file.txt"), "hi");
    assert_eq!(read_from(&disk, &format!("{ROOT}/plain")), None);
}

#[test]
fn read_standardizes_the_cwd_first() {
    // "repo/./src/../src" is the same place; the walk must not stop at a
    // half-climbed path with a `..` still in it.
    let disk = MemoryDisk::default()
        .dir(&format!("{ROOT}/repo/.git"))
        .head(&format!("{ROOT}/repo/.git"), "ref: refs/heads/main\n");
    assert_eq!(
        read_from(&disk, &format!("{ROOT}/repo/./src/../src")),
        info("main", false)
    );
}

// MARK: - submodule vs linked worktree

#[test]
fn submodule_under_worktrees_dir_is_not_a_worktree() {
    // Primary checkout lives under a directory literally named "worktrees";
    // a submodule's gitdir pointer resolves to .git/modules/… — it must not
    // be flagged as a linked worktree.
    let disk = MemoryDisk::default()
        .dir(&format!("{ROOT}/worktrees/repo/.git"))
        .head(
            &format!("{ROOT}/worktrees/repo/.git/modules/sub"),
            "ref: refs/heads/main\n",
        )
        .file(
            &format!("{ROOT}/worktrees/repo/sub/.git"),
            &format!("gitdir: {ROOT}/worktrees/repo/.git/modules/sub\n"),
        );
    assert_eq!(
        read_from(&disk, &format!("{ROOT}/worktrees/repo/sub")),
        info("main", false)
    );
}

// MARK: - depth cap

#[test]
fn the_walk_gives_up_after_twelve_levels() {
    // A `.git` above the cap is never seen: a bogus cwd must not scan the
    // whole filesystem upward.
    let deep: String = (0..13).fold(ROOT.to_owned(), |path, level| format!("{path}/d{level}"));
    let disk = MemoryDisk::default()
        .dir(&format!("{ROOT}/.git"))
        .head(&format!("{ROOT}/.git"), "ref: refs/heads/main\n");
    assert_eq!(read_from(&disk, &deep), None);

    let within_cap: String =
        (0..11).fold(ROOT.to_owned(), |path, level| format!("{path}/d{level}"));
    assert_eq!(read_from(&disk, &within_cap), info("main", false));
}
