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
            #"do shell script "/bin/ln -sfh " & "#
                + #"quoted form of "/Applications/Hibiki.app/Contents/MacOS/hibiki-cli" & " " & "#
                + #"quoted form of "/usr/local/bin/hibiki" with administrator privileges"#
        )
    }

    /// Regression: the bundle path was pasted between single quotes inside a root shell
    /// command, so a quote in the app's path broke out of the quoting.
    func testHostilePathStaysASingleShellWord() throws {
        // Paths that exist nowhere: even if the probe below ever stopped replacing the
        // command, the unprivileged `ln` could only fail.
        let installPath = "/nonexistent-hibiki-test-dir/bin/hibiki"
        let hostile = #"/nonexistent-hibiki-test-dir/It's "Hibiki" $(touch /tmp/hibiki-test-pwned) \ `id`.app/hibiki-cli"#
        let script = CLIInstaller.adminInstallScript(installPath: installPath, bundledPath: hostile)

        // Same script with the command swapped for a harmless one and without privileges:
        // the shell must hand each path back as exactly one, unmodified argument.
        let command = "/bin/ln -sfh "
        let privileges = " with administrator privileges"
        XCTAssertTrue(script.contains(command) && script.hasSuffix(privileges), "script shape changed; update the probe")
        let probe = script
            .replacingOccurrences(of: command, with: "/usr/bin/printf '%s\\\\n' ")
            .replacingOccurrences(of: privileges, with: "")
        XCTAssertFalse(probe.contains("/bin/ln"))

        var error: NSDictionary?
        let output = NSAppleScript(source: probe)?.executeAndReturnError(&error).stringValue
        XCTAssertNil(error, "probe script failed: \(String(describing: error))")

        let lines = try XCTUnwrap(output).split(whereSeparator: \.isNewline).map(String.init)
        XCTAssertEqual(lines, [hostile, installPath])
        XCTAssertFalse(FileManager.default.fileExists(atPath: "/tmp/hibiki-test-pwned"))
    }
}
