import Foundation

/// Manages CLI tool installation by creating/removing symlinks to /usr/local/bin
final class CLIInstaller {
    static let shared = CLIInstaller()

    private let installPath = "/usr/local/bin/hibiki"
    private let logger = DebugLogger.shared

    private init() {}

    /// Path to the CLI tool bundled inside the app
    var bundledCLIPath: String? {
        guard let appPath = Bundle.main.bundlePath as String?,
              appPath.hasSuffix(".app") else {
            return nil
        }
        return "\(appPath)/Contents/MacOS/hibiki-cli"
    }

    /// Check if CLI is installed at /usr/local/bin/hibiki
    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: installPath)
    }

    /// Check if CLI is correctly linked to current app bundle
    var isCorrectlyLinked: Bool {
        guard let bundledPath = bundledCLIPath else { return false }

        do {
            let linkDestination = try FileManager.default.destinationOfSymbolicLink(atPath: installPath)
            // Resolve relative paths
            let resolvedDestination = (linkDestination as NSString).standardizingPath
            let resolvedBundled = (bundledPath as NSString).standardizingPath
            return resolvedDestination == resolvedBundled
        } catch {
            // Not a symlink or doesn't exist
            return false
        }
    }

    /// Check if app is running from /Applications
    var isRunningFromApplications: Bool {
        guard let appPath = Bundle.main.bundlePath as String? else { return false }
        return appPath.hasPrefix("/Applications/")
    }

    /// Check if CLI installation should be offered
    /// Returns true if app is in /Applications and CLI is not correctly linked
    var shouldOfferInstallation: Bool {
        isRunningFromApplications && !isCorrectlyLinked
    }

    /// Install CLI by creating symlink (may require admin privileges)
    /// - Returns: Result with success or error message
    func install() -> Result<Void, CLIInstallError> {
        guard let bundledPath = bundledCLIPath else {
            logger.error("Cannot find bundled CLI path", source: "CLIInstaller")
            return .failure(.bundledCLINotFound)
        }

        // Check if bundled CLI exists
        guard FileManager.default.fileExists(atPath: bundledPath) else {
            logger.error("Bundled CLI does not exist at: \(bundledPath)", source: "CLIInstaller")
            return .failure(.bundledCLINotFound)
        }

        // Ensure /usr/local/bin exists
        let binDir = "/usr/local/bin"
        if !FileManager.default.fileExists(atPath: binDir) {
            logger.error("/usr/local/bin does not exist", source: "CLIInstaller")
            return .failure(.binDirNotFound)
        }

        // Remove an existing file or symlink. `fileExists` follows links and so misses a
        // dangling one (app moved or renamed), which would then block the new link.
        if (try? FileManager.default.attributesOfItem(atPath: installPath)) != nil {
            do {
                try FileManager.default.removeItem(atPath: installPath)
                logger.info("Removed existing file at \(installPath)", source: "CLIInstaller")
            } catch {
                logger.error("Failed to remove existing file: \(error)", source: "CLIInstaller")
                return .failure(.permissionDenied)
            }
        }

        // Create symlink
        do {
            try FileManager.default.createSymbolicLink(atPath: installPath, withDestinationPath: bundledPath)
            logger.info("Created symlink: \(installPath) -> \(bundledPath)", source: "CLIInstaller")
            return .success(())
        } catch {
            logger.error("Failed to create symlink: \(error)", source: "CLIInstaller")
            return .failure(.permissionDenied)
        }
    }

    /// Install the CLI symlink. Asks for administrator privileges only when creating the
    /// link as the current user fails (on many Macs /usr/local/bin is user-writable).
    func installWithAdminPrivileges(completion: @escaping (Result<Void, CLIInstallError>) -> Void) {
        guard let bundledPath = bundledCLIPath else {
            completion(.failure(.bundledCLINotFound))
            return
        }

        // Check if bundled CLI exists
        guard FileManager.default.fileExists(atPath: bundledPath) else {
            completion(.failure(.bundledCLINotFound))
            return
        }

        if case .success = install() {
            completion(.success(()))
            return
        }

        let script = Self.adminInstallScript(installPath: installPath, bundledPath: bundledPath)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)

                DispatchQueue.main.async {
                    if let error = error {
                        let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                        self?.logger.error("AppleScript error: \(errorMessage)", source: "CLIInstaller")

                        // Check if user cancelled
                        if errorMessage.contains("User canceled") || errorMessage.contains("cancelled") {
                            completion(.failure(.userCancelled))
                        } else {
                            completion(.failure(.permissionDenied))
                        }
                    } else {
                        self?.logger.info("CLI installed successfully with admin privileges", source: "CLIInstaller")
                        completion(.success(()))
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self?.logger.error("Failed to create AppleScript", source: "CLIInstaller")
                    completion(.failure(.scriptError))
                }
            }
        }
    }

    /// AppleScript that creates the symlink as root.
    ///
    /// The app bundle can live at any path, and that path ends up in a root shell command.
    /// Each path is therefore an escaped AppleScript string literal passed through
    /// `quoted form of`, which is AppleScript's shell quoting, instead of being pasted
    /// between hand-written single quotes.
    static func adminInstallScript(installPath: String, bundledPath: String) -> String {
        func literal(_ path: String) -> String {
            let escaped = path
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }

        // One `ln -sfh`: replace the link itself, never follow an existing link at the
        // install path into another directory, and leave no gap between remove and create.
        let install = "quoted form of \(literal(installPath))"
        let bundled = "quoted form of \(literal(bundledPath))"
        return "do shell script \"/bin/ln -sfh \" & \(bundled) & \" \" & \(install)"
            + " with administrator privileges"
    }

    /// Uninstall CLI by removing symlink
    func uninstall() -> Result<Void, CLIInstallError> {
        guard FileManager.default.fileExists(atPath: installPath) else {
            return .success(()) // Already uninstalled
        }

        do {
            try FileManager.default.removeItem(atPath: installPath)
            logger.info("Removed CLI symlink at \(installPath)", source: "CLIInstaller")
            return .success(())
        } catch {
            logger.error("Failed to remove CLI symlink: \(error)", source: "CLIInstaller")
            return .failure(.permissionDenied)
        }
    }
}

enum CLIInstallError: LocalizedError {
    case bundledCLINotFound
    case binDirNotFound
    case permissionDenied
    case userCancelled
    case scriptError

    var errorDescription: String? {
        switch self {
        case .bundledCLINotFound:
            return "The CLI tool was not found in the app bundle."
        case .binDirNotFound:
            return "/usr/local/bin directory does not exist."
        case .permissionDenied:
            return "Permission denied. Administrator privileges may be required."
        case .userCancelled:
            return "Installation was cancelled."
        case .scriptError:
            return "Failed to run installation script."
        }
    }
}
