import XCTest
@testable import CodeIslandCore

final class PromptTextCleanerTests: XCTestCase {
    func testLeadingPastedScreenshotPathStripped() {
        let raw = "/var/folders/q6/s0n344p10g3f8gky5rb347w00000gn/T/TemporaryItems/NSIRD_screencaptureui_xo27fr/Screenshot\\ 2026-10-26\\ at\\ 03.58.58.png  tulisan ini kira2 bisa diganti ngga? misal agents atau agent apa yang sesuai"
        let cleaned = PromptTextCleaner.cleanPrompt(raw)
        XCTAssertEqual(cleaned, "tulisan ini kira2 bisa diganti ngga? misal agents atau agent apa yang sesuai")
    }

    func testEmbeddedScreenshotPathStripped() {
        let raw = "fitur apalagi yang perlu/ optimize/var/folders/q6/s0n344p10g3f8gky5rb347w00000gn/T/TemporaryItems/NSIRD_screencaptureui_LGVSBl/Screenshot\\ 2026-10-26\\ at\\ 04.19.55.png  malah jadi gini anjay var/dll bukan user question"
        let cleaned = PromptTextCleaner.cleanPrompt(raw)
        XCTAssertEqual(cleaned, "fitur apalagi yang perlu/ optimize malah jadi gini anjay var/dll bukan user question")
    }

    func testScreenshotWithoutEscapedSpaces() {
        let raw = "/var/folders/q6/s0n344p10g3f8gky5rb347w00000gn/T/TemporaryItems/NSIRD_screencaptureui_44wkY6/Screenshot 2026-10-26 at 04.08.01.png ganti agents aja"
        let cleaned = PromptTextCleaner.cleanPrompt(raw)
        XCTAssertEqual(cleaned, "ganti agents aja")
    }

    func testOnlyImagePathReturnsNil() {
        let raw = "/var/folders/q6/s0n344p10g3f8gky5rb347w00000gn/T/TemporaryItems/NSIRD_screencaptureui_44wkY6/Screenshot 2026-10-26 at 04.08.01.png"
        let cleaned = PromptTextCleaner.cleanPrompt(raw)
        XCTAssertNil(cleaned)
    }

    func testMarkdownImageAndXmlTagsStripped() {
        let raw = "<USER_REQUEST>![Screenshot](/Users/test/image.png) Tolong rapikan layout notch</USER_REQUEST>"
        let cleaned = PromptTextCleaner.cleanPrompt(raw)
        XCTAssertEqual(cleaned, "Tolong rapikan layout notch")
    }
}
