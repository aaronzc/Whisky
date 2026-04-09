//
//  Winetricks.swift
//  Whisky
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
import AppKit
import WhiskyKit

enum WinetricksCategories: String {
    case apps
    case benchmarks
    case dlls
    case fonts
    case games
    case settings
}

struct WinetricksVerb: Identifiable {
    var id = UUID()

    var name: String
    var description: String
}

struct WinetricksCategory {
    var category: WinetricksCategories
    var verbs: [WinetricksVerb]
}

class Winetricks {
    static let winetricksURL: URL = WhiskyWineInstaller.libraryFolder
        .appending(path: "winetricks")
    private static let verbsURL: URL = WhiskyWineInstaller.libraryFolder
        .appending(path: "verbs.txt")
    private static let bundledWinetricksURL = Bundle.main.url(forResource: "winetricks",
                                                              withExtension: nil,
                                                              subdirectory: "Winetricks")
        ?? Bundle.main.url(forResource: "winetricks", withExtension: nil)
    private static let bundledVerbsURL = Bundle.main.url(forResource: "verbs",
                                                         withExtension: "txt",
                                                         subdirectory: "Winetricks")
        ?? Bundle.main.url(forResource: "verbs", withExtension: "txt")

    static func runCommand(command: String, bottle: Bottle) async {
        await ensureResources()
        guard let resourcesURL = Bundle.main.url(forResource: "cabextract", withExtension: nil)?
            .deletingLastPathComponent() else { return }
        // swiftlint:disable:next line_length
        let winetricksCmd = #"PATH=\"\#(WhiskyWineInstaller.binFolder.path):\#(resourcesURL.path(percentEncoded: false)):$PATH\" WINE=wine64 WINEPREFIX=\"\#(bottle.url.path)\" \"\#(winetricksURL.path(percentEncoded: false))\" \#(command)"#

        let script = """
        tell application "Terminal"
            activate
            do script "\(winetricksCmd)"
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)

            if let error = error {
                print(error)
                if let description = error["NSAppleScriptErrorMessage"] as? String {
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = String(localized: "alert.message")
                        alert.informativeText = String(localized: "alert.info")
                            + " \(command): "
                            + description
                        alert.alertStyle = .critical
                        alert.addButton(withTitle: String(localized: "button.ok"))
                        alert.runModal()
                    }
                }
            }
        }
    }

    static func parseVerbs(bottle: Bottle) async -> [WinetricksCategory] {
        await ensureResources()
        var verbs: String = (try? String(contentsOf: verbsURL, encoding: .utf8)) ?? ""
        if verbs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !verbs.contains("=====") {
            await copyBundledResources()
            verbs = (try? String(contentsOf: verbsURL, encoding: .utf8)) ?? ""
            if verbs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let bundledVerbsURL,
               let bundledVerbs = try? String(contentsOf: bundledVerbsURL, encoding: .utf8) {
                verbs = bundledVerbs
            }
        }

        // Read the file line by line
        let lines = verbs.components(separatedBy: "\n")
        var categories: [WinetricksCategory] = []
        var currentCategory: WinetricksCategory?

        for line in lines {
            // Categories are label as "===== <name> ====="
            if line.starts(with: "=====") {
                // If we have a current category, add it to the list
                if let currentCategory = currentCategory {
                    categories.append(currentCategory)
                }

                // Create a new category
                // Capitalize the first letter of the category name
                let categoryName = line.replacingOccurrences(of: "=====", with: "").trimmingCharacters(in: .whitespaces)
                if let cateogry = WinetricksCategories(rawValue: categoryName) {
                    currentCategory = WinetricksCategory(category: cateogry,
                                                         verbs: [])
                } else {
                    currentCategory = nil
                }
            } else {
                guard currentCategory != nil else {
                    continue
                }

                // If we have a current category, add the verb to it
                // Verbs eg. "3m_library               3M Cloud Library (3M Company, 2015) [downloadable]"
                let verbName = line.components(separatedBy: " ")[0]
                let verbDescription = line.replacingOccurrences(of: "\(verbName) ", with: "")
                    .trimmingCharacters(in: .whitespaces)
                currentCategory?.verbs.append(WinetricksVerb(name: verbName, description: verbDescription))
            }
        }

        // Add the last category
        if let currentCategory = currentCategory {
            categories.append(currentCategory)
        }

        return categories
    }

    private static func ensureResources() async {
        do {
            try FileManager.default.createDirectory(at: WhiskyWineInstaller.libraryFolder,
                                                    withIntermediateDirectories: true)
        } catch {
            return
        }
        await copyBundledResources()
    }

    private static func copyBundledResources() async {
        if !FileManager.default.fileExists(atPath: winetricksURL.path),
           let bundledWinetricksURL {
            try? FileManager.default.copyItem(at: bundledWinetricksURL, to: winetricksURL)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: winetricksURL.path
            )
        }

        let verbsContent = (try? String(contentsOf: verbsURL, encoding: .utf8)) ?? ""
        if verbsContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !verbsContent.contains("====="),
           let bundledVerbsURL {
            try? FileManager.default.removeItem(at: verbsURL)
            try? FileManager.default.copyItem(at: bundledVerbsURL, to: verbsURL)
        }
    }
}
