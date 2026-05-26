import CWinRT
import WindowsFoundation

@main
struct App {
    static func main() {
        RoInitialize(RO_INIT_TYPE(1))  // Initialize COM for WinRT

        let uri = Uri("https://www.swift.org/path?query=hello")
        print("AbsoluteUri: \(uri.absoluteUri)")
        print("SchemeName: \(uri.schemeName)")
        print("Host: \(uri.host)")
        print("Path: \(uri.path)")
        print("Query: \(uri.query)")
    }
}
