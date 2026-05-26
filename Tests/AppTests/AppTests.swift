import Testing
import WindowsFoundation
import CWinRT

struct UriTests {

    init() {
        RoInitialize(RO_INIT_TYPE(1))  // Initialize COM for WinRT
    }

    @Test func properties() {
        let uri = Uri("https://www.swift.org/path?query=hello")
        #expect(uri.absoluteUri == "https://www.swift.org/path?query=hello")
        #expect(uri.schemeName == "https")
        #expect(uri.host == "www.swift.org")
        #expect(uri.path == "/path")
        #expect(uri.query == "?query=hello")
    }

    @Test func port() {
        let uri = Uri("http://localhost:8080/test")
        #expect(uri.host == "localhost")
        #expect(uri.port == 8080)
    }

    @Test func fragment() {
        let uri = Uri("https://example.com/page#section")
        #expect(uri.fragment == "#section")
    }

    @Test func relativeUri() {
        let base = Uri("https://example.com/base/")
        let relative = try? base.combineUri("child")
        #expect(relative?.absoluteUri == "https://example.com/base/child")
    }

    @Test func staticEscaping() {
        let escaped = try? Uri.escapeComponent("hello world")
        #expect(escaped == "hello%20world")
        let unescaped = try? Uri.unescapeComponent("hello%20world")
        #expect(unescaped == "hello world")
    }
}
