import XCTest
@testable import OpenUsageCLI

final class AppBundleLocatorTests: XCTestCase {
    func testFindsContainingAppThroughHelperSymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = root.appendingPathComponent("Brim.app")
        let contents = app.appendingPathComponent("Contents")
        let helpers = contents.appendingPathComponent("Helpers")
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.example.brim",
            "CFBundleShortVersionString": "1.2.3"
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: contents.appendingPathComponent("Info.plist"))
        let helper = helpers.appendingPathComponent("brim")
        try Data().write(to: helper)
        let symlink = bin.appendingPathComponent("brim")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: helper)
        defer { try? FileManager.default.removeItem(at: root) }

        let located = AppBundleLocator.locate(executableURL: symlink)

        XCTAssertEqual(located.bundleIdentifier, "com.example.brim")
        XCTAssertEqual(located.version, "1.2.3")
    }

    func testBareExecutableFallsBackToTheReleaseBundle() {
        let located = AppBundleLocator.locate(
            executableURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)/brim")
        )

        XCTAssertEqual(located.bundleIdentifier, "com.tapariapurv.brim")
        XCTAssertNil(located.version)
    }
}
