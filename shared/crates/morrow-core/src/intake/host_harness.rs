//! Path helpers of `macos/Sources/MorrowCore/HostHarness.swift` that intake uses.

/// `HostHarnessResolver.outermostAppBundlePath(forExecutable:)`: the path
/// up to the first component ending in `.app`, any case.
pub fn outermost_app_bundle_path(path: &str) -> Option<String> {
    let components = path_components(path);
    let index = components
        .iter()
        .position(|c| c.to_lowercase().ends_with(".app"))?;
    Some(join(&components[..=index], path.starts_with('/')))
}

/// `URL(fileURLWithPath:).standardizedFileURL.path` for an absolute path:
/// `.` and `..` resolved, repeated and trailing slashes dropped. Symlinks
/// are not followed (Swift's does not either).
pub fn standardized(path: &str) -> String {
    let mut out: Vec<&str> = Vec::new();
    for component in path_components(path) {
        match component {
            "." => {}
            ".." => {
                out.pop();
            }
            other => out.push(other),
        }
    }
    join(&out, path.starts_with('/'))
}

/// `deletingLastPathComponent().path`.
pub fn deleting_last_path_component(path: &str) -> String {
    let mut components = path_components(path);
    components.pop();
    join(&components, path.starts_with('/'))
}

fn path_components(path: &str) -> Vec<&str> {
    path.split('/').filter(|c| !c.is_empty()).collect()
}

fn join(components: &[&str], absolute: bool) -> String {
    let joined = components.join("/");
    if absolute {
        format!("/{joined}")
    } else {
        joined
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn app_bundle_and_standardized_paths() {
        assert_eq!(
            outermost_app_bundle_path(
                "/A/ChatGPT.app/Contents/Resources/x/Codex.app/Contents/MacOS/codex"
            )
            .as_deref(),
            Some("/A/ChatGPT.app")
        );
        assert_eq!(outermost_app_bundle_path("/usr/bin/codex"), None);
        assert_eq!(standardized("/a/./b/../c//d/"), "/a/c/d");
        assert_eq!(deleting_last_path_component("/a/b/c"), "/a/b");
    }
}
