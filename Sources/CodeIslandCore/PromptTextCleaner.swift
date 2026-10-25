import Foundation

public enum PromptTextCleaner {
    /// Cleans and extracts human-readable text from raw user prompts.
    /// Strips pasted image/screenshot file paths (e.g. `/var/folders/...`, `/Users/...`, `~/...`),
    /// markdown image syntax `![...](...)`, XML tags `<tag>...</tag>`, and leftover delimiters.
    /// Returns `nil` if nothing meaningful remains (e.g. prompt was purely a screenshot/image path).
    public static func cleanPrompt(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }

        // Strip XML wrappers like <USER_REQUEST> ... </USER_REQUEST> or <tag> ... </tag>
        text = text.replacingOccurrences(of: #"</?[A-Za-z0-9_-]+(\s+[^>]*)?>"#, with: " ", options: .regularExpression)

        // Strip markdown image syntax: ![alt](url)
        text = text.replacingOccurrences(of: #"!\[.*?\]\([^\)]*\)"#, with: " ", options: .regularExpression)

        // Strip image/file paths:
        // Matches /var/folders/..., /private/var/..., /Users/..., ~/..., etc.
        // Handles escaped spaces like "\ " in macOS screenshots
        let pathRegex = #"(?:/(?:var|private/var|Users|tmp|System|Volumes|Applications)|\~)(?:/[^\s\n]+|\\\s|[^\n])*\.(?:png|jpe?g|gif|webp|tiff|heic|bmp|svg)\b"#
        text = text.replacingOccurrences(of: pathRegex, with: " ", options: [.regularExpression, .caseInsensitive])

        // Strip remaining bare /var/folders/ or /tmp/ paths even without extension
        let varFoldersPattern = #"(?:/(?:var/folders|private/var/folders|tmp)/[^\s\n]+)"#
        text = text.replacingOccurrences(of: varFoldersPattern, with: " ", options: .regularExpression)

        // Strip escaped spaces leftover: "\ " -> " "
        text = text.replacingOccurrences(of: #"\ "#, with: " ")

        // Split into non-empty lines and join
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let joined = lines.joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: " /\\:;,-_\"'()[]{}")))

        if joined.isEmpty || joined.count < 2 {
            return nil
        }
        return joined
    }
}
