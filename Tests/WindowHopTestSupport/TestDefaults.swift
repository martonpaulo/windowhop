import Foundation

/// A throwaway `UserDefaults` suite for one test, the only way a test makes one
/// (`scripts/validate.sh` enforces this).
///
/// The suite name is an absolute path under `$TMPDIR/windowhop-tests/`, so cfprefsd
/// writes the suite's plist there and never in `~/Library/Preferences`. A named
/// suite cannot be kept out of `~/Library/Preferences` by teardown:
/// `removePersistentDomain(forName:)` only empties the domain, and cfprefsd writes
/// the empty domain back to `<name>.plist` after the test process exits, even
/// when teardown deleted the file (#129). macOS purges what is left in `$TMPDIR`.
public struct TestDefaults {
    public struct Unavailable: Error {
        public let suiteName: String
    }

    public static let directory = FileManager.default.temporaryDirectory
        .appending(path: "windowhop-tests", directoryHint: .isDirectory)

    public let suiteName: String
    public let defaults: UserDefaults

    public init() throws {
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        suiteName = Self.directory
            .appending(path: "windowhop-tests-\(UUID().uuidString)")
            .path(percentEncoded: false)
        defaults = try Self.open(suiteName)
    }

    /// A second `UserDefaults` over the same suite, as a relaunched app would read it.
    public func reopen() throws -> UserDefaults {
        try Self.open(suiteName)
    }

    /// What the suite stores itself, without the process-wide registration domain.
    public var persistentDomain: [String: Any]? {
        defaults.persistentDomain(forName: suiteName)
    }

    public func remove() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private static func open(_ suiteName: String) throws -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw Unavailable(suiteName: suiteName)
        }
        return defaults
    }
}
