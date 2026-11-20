//! Reminders through WinRT toasts (#107).
//!
//! A toast needs an application id the shell knows: the one the Start menu entry
//! was registered with, which for this app is the bundle identifier Windows was
//! told about at install time. That is why the ticket's criterion says to test
//! notifications **with the app installed** — from a bare `cargo run` there is
//! no registered id and Windows drops the toast.

use windows::UI::Notifications::{ToastNotification, ToastNotificationManager};
use windows::core::HSTRING;

/// The id the NSIS installer registers; a dev build falls back to it too.
pub const APP_ID: &str = "dev.morrow.desktop";

/// Shows one reminder. An error is the sentence the caller logs.
pub fn notify(title: &str, body: &str) -> Result<(), String> {
    let xml = toast_xml(title, body);
    let document = windows::Data::Xml::Dom::XmlDocument::new().map_err(|error| error.message())?;
    document
        .LoadXml(&HSTRING::from(xml))
        .map_err(|error| error.message())?;
    let toast =
        ToastNotification::CreateToastNotification(&document).map_err(|error| error.message())?;
    ToastNotificationManager::CreateToastNotifierWithId(&HSTRING::from(APP_ID))
        .map_err(|error| error.message())?
        .Show(&toast)
        .map_err(|error| error.message())
}

/// The toast's XML. Escaped by hand rather than through the DOM: the text comes
/// from a session title, and a `<` in a song name must not become markup.
pub fn toast_xml(title: &str, body: &str) -> String {
    format!(
        "<toast><visual><binding template=\"ToastGeneric\">\
         <text>{}</text><text>{}</text>\
         </binding></visual></toast>",
        escape(title),
        escape(body)
    )
}

fn escape(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}
