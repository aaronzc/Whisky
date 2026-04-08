//
//  WhiskyWineInstaller.swift
//  WhiskyKit
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import Foundation
import SemanticVersion

public class WhiskyWineInstaller {
    private static let defaultDownloadURL = "https://data.getwhisky.app/Wine/Libraries.tar.gz"
    private static let defaultVersionPlistURL = "https://data.getwhisky.app/Wine/WhiskyWineVersion.plist"

    private static func bundledString(forKey key: String) -> String? {
        return Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    public static func whiskyWineDownloadURL() -> URL? {
        let urlString = bundledString(forKey: "WhiskyWineDownloadURL") ?? defaultDownloadURL
        return URL(string: urlString)
    }

    public static func whiskyWineVersionPlistURL() -> URL? {
        let urlString = bundledString(forKey: "WhiskyWineVersionPlistURL") ?? defaultVersionPlistURL
        return URL(string: urlString)
    }

    /// The Whisky application folder
    public static let applicationFolder = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appending(path: Bundle.whiskyBundleIdentifier)

    /// The folder of all the libfrary files
    public static let libraryFolder = applicationFolder.appending(path: "Libraries")

    /// URL to the installed `wine` `bin` directory
    public static let binFolder: URL = libraryFolder.appending(path: "Wine").appending(path: "bin")

    public static func isWhiskyWineInstalled() -> Bool {
        return whiskyWineVersion() != nil
    }

    public static func install(from: URL) {
        do {
            if !FileManager.default.fileExists(atPath: applicationFolder.path) {
                try FileManager.default.createDirectory(at: applicationFolder, withIntermediateDirectories: true)
            } else {
                // Recreate it
                try FileManager.default.removeItem(at: applicationFolder)
                try FileManager.default.createDirectory(at: applicationFolder, withIntermediateDirectories: true)
            }

            try Tar.untar(tarBall: from, toURL: applicationFolder)
            try normalizeWineInstall()
            try FileManager.default.removeItem(at: from)
        } catch {
            print("Failed to install WhiskyWine: \(error)")
        }
    }

    public static func uninstall() {
        do {
            try FileManager.default.removeItem(at: libraryFolder)
        } catch {
            print("Failed to uninstall WhiskyWine: \(error)")
        }
    }

    public static func shouldUpdateWhiskyWine() async -> (Bool, SemanticVersion) {
        let localVersion = whiskyWineVersion()

        var remoteVersion: SemanticVersion?

        if let remoteUrl = whiskyWineVersionPlistURL() {
            remoteVersion = await withCheckedContinuation { continuation in
                URLSession(configuration: .ephemeral).dataTask(with: URLRequest(url: remoteUrl)) { data, _, error in
                    do {
                        if error == nil, let data = data {
                            let decoder = PropertyListDecoder()
                            let remoteInfo = try decoder.decode(WhiskyWineVersion.self, from: data)
                            let remoteVersion = remoteInfo.version

                            continuation.resume(returning: remoteVersion)
                            return
                        }
                        if let error = error {
                            print(error)
                        }
                    } catch {
                        print(error)
                    }

                    continuation.resume(returning: nil)
                }.resume()
            }
        }

        if let localVersion = localVersion, let remoteVersion = remoteVersion {
            if localVersion < remoteVersion {
                return (true, remoteVersion)
            }
        }

        return (false, SemanticVersion(0, 0, 0))
    }

    public static func whiskyWineVersion() -> SemanticVersion? {
        do {
            let versionPlist = libraryFolder
                .appending(path: "WhiskyWineVersion")
                .appendingPathExtension("plist")

            let decoder = PropertyListDecoder()
            let data = try Data(contentsOf: versionPlist)
            let info = try decoder.decode(WhiskyWineVersion.self, from: data)
            return info.version
        } catch {
            print(error)
            return nil
        }
    }

    private static func normalizeWineInstall() throws {
        if !FileManager.default.fileExists(atPath: libraryFolder.path) {
            try FileManager.default.createDirectory(at: libraryFolder, withIntermediateDirectories: true)
        }

        let wineDir = libraryFolder.appending(path: "Wine")
        if !FileManager.default.fileExists(atPath: wineDir.path) {
            if let appWineDir = findWineAppResources() {
                // Move the embedded wine directory into Libraries/Wine
                try FileManager.default.moveItem(at: appWineDir, to: wineDir)
            }
        }

        // Ensure wine64 entry points exist (Whisky expects wine64)
        let wineBin = wineDir.appending(path: "bin")
        let wine = wineBin.appending(path: "wine")
        let wine64 = wineBin.appending(path: "wine64")
        let wine64Preloader = wineBin.appending(path: "wine64-preloader")

        if FileManager.default.fileExists(atPath: wine.path) {
            if !FileManager.default.fileExists(atPath: wine64.path) {
                try FileManager.default.createSymbolicLink(at: wine64, withDestinationURL: wine)
            }
            if !FileManager.default.fileExists(atPath: wine64Preloader.path) {
                try FileManager.default.createSymbolicLink(at: wine64Preloader, withDestinationURL: wine)
            }
        }

        if whiskyWineVersion() == nil, FileManager.default.fileExists(atPath: wine64.path) {
            try writeWhiskyWineVersion(from: wine64)
        }
    }

    private static func findWineAppResources() -> URL? {
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: applicationFolder,
                                                                      includingPropertiesForKeys: nil)
            for url in contents where url.pathExtension == "app" {
                let candidate = url.appending(path: "Contents")
                    .appending(path: "Resources")
                    .appending(path: "wine")
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        } catch {
            print("Failed to scan for Wine app resources: \(error)")
        }
        return nil
    }

    private static func writeWhiskyWineVersion(from wineBinary: URL) throws {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = wineBinary
        process.arguments = ["--version"]
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()

        let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        let versionString = parseWineVersion(output: output)
        let version = SemanticVersion(versionString) ?? SemanticVersion(0, 0, 0)

        let info = WhiskyWineVersion(version: version)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let plistData = try encoder.encode(info)
        let versionPlist = libraryFolder
            .appending(path: "WhiskyWineVersion")
            .appendingPathExtension("plist")
        try plistData.write(to: versionPlist)
    }

    private static func parseWineVersion(output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: "wine-") {
            let after = trimmed[range.upperBound...]
            if let space = after.firstIndex(where: { $0.isWhitespace }) {
                return String(after[..<space])
            }
            return String(after)
        }
        return trimmed
    }
}

struct WhiskyWineVersion: Codable {
    var version: SemanticVersion = SemanticVersion(1, 0, 0)
}
