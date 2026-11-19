//! The hook command. See the library docs.

fn main() {
    #[cfg(unix)]
    morrow_bridge::run::run();
    std::process::exit(0);
}
