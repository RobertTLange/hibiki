import XCTest
@testable import Hibiki

final class CLIInstallerScriptTests: XCTestCase {
    func testPlainPaths() {
        let script = CLIInstaller.adminInstallScript(
            installPath: "/usr/local/bin/hibiki",
            bundledPath: "/Applications/Hibiki.app/Contents/MacOS/hibiki-cli"
        )
        XCTAssertEqual(
            script,
            #"do shell script "/bin/rm -f " & quoted form of "/usr/local/bin/hibiki" & " && /bin/ln -s " & "#
                + #"quoted form of "/Applications/Hibiki.app/Contents/MacOS/hibiki-cli" & " " & "#
                + #"quoted form of "/usr/local/bin/hibiki" with administrator privileges"#
        )
    }

    /// Regression: the bundle path was pasted between single quotes inside a root shell
    /// command, so a quote in the app's path broke out of the quoting.
    func testHostilePathStaysASingleShellWord() throws {
        let hostile = #"/Applications/It's "Hibiki" $(touch /tmp/pwned) \ `id`.app/Contents/MacOS/hibiki-cli"#
        let script = CLIInstaller.adminInstallScript(installPath: "/usr/local/bin/hibiki", bundledPath: hostile)

        // Same script with the privileged commands swapped for a harmless one: the shell
        // must hand the path back as exactly one, unmodified argument.
        let probe = script
            .replacingOccurrences(of: "/bin/rm -f ", with: "/usr/bin/printf '%s\\\\n' ")
            .replacingOccurrences(of: " && /bin/ln -s ", with: " ")
            .replacingOccurrences(of: " with administrator privileges", with: "")

        var error: NSDictionary?
        let output = NSAppleScript(source: probe)?.executeAndReturnError(&error).stringValue
        XCTAssertNil(error, "probe script failed: \(String(describing: error))")

        let lines = try XCTUnwrap(output).split(whereSeparator: \.isNewline).map(String.init)
        XCTAssertEqual(lines, ["/usr/local/bin/hibiki", hostile, "/usr/local/bin/hibiki"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: "/tmp/pwned"))
    }
}
