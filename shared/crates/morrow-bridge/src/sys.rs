//! The one call std does not offer on stable: this process's uid.
#![allow(unsafe_code)]

/// The real uid of this process.
pub(crate) fn current_uid() -> u32 {
    // SAFETY: getuid(2) takes no arguments, cannot fail and touches no memory.
    unsafe { libc::getuid() }
}
