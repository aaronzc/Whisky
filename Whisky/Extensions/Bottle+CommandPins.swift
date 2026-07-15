//
//  Bottle+CommandPins.swift
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

// swiftlint:disable file_length

private actor CommandPinLaunchGuard {
    static let shared = CommandPinLaunchGuard()
    private var launching: Set<UUID> = []

    func acquire(_ id: UUID) -> Bool {
        if launching.contains(id) {
            return false
        }
        launching.insert(id)
        return true
    }

    func release(_ id: UUID) {
        launching.remove(id)
    }
}

extension Bottle {
    func runCommandPin(_ pin: PinnedProgram) {
        let pinID = pin.id
        let pinName = pin.name
        let pinArguments = pin.arguments

        Task(priority: .userInitiated) {
            let acquired = await CommandPinLaunchGuard.shared.acquire(pinID)
            if !acquired {
                Wine.activateWineApp()
                return
            }

            guard let commandURL = self.resolveCommandURL(for: pin) else {
                await self.showCommandPinError(name: pinName, message: "The command could not be resolved.")
                await CommandPinLaunchGuard.shared.release(pinID)
                return
            }

            let imageName = commandURL.lastPathComponent
            let lowercasedName = imageName.lowercased()

            if lowercasedName == "cmd.exe" {
                await self.launchCommandPinConsole(arguments: pinArguments)
                await CommandPinLaunchGuard.shared.release(pinID)
                return
            }

            if commandURL.pathExtension.lowercased() == "exe",
               await Wine.isProcessRunning(bottle: self, imageName: imageName) {
                Wine.activateWineApp()
                await CommandPinLaunchGuard.shared.release(pinID)
                return
            }

            do {
                if commandURL.pathExtension.lowercased() == "bat" {
                    try await Wine.runBatchFile(url: commandURL, bottle: self)
                } else {
                    try await Wine.runProgram(
                        at: commandURL,
                        args: self.parseCommandArguments(pinArguments),
                        bottle: self
                    )
                }

                if commandURL.pathExtension.lowercased() == "exe" {
                    if await Wine.isProcessRunning(bottle: self, imageName: imageName) {
                        Wine.activateWineApp()
                    } else {
                        _ = await Wine.waitForProcessStart(bottle: self, imageName: imageName)
                    }
                }
            } catch {
                await self.showCommandPinError(name: pinName, message: error.localizedDescription)
            }

            await CommandPinLaunchGuard.shared.release(pinID)
        }
    }

    func resolveCommandURL(for pin: PinnedProgram) -> URL? {
        let trimmed = pin.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("/") {
            return existingFileURL(URL(filePath: trimmed))
        }

        if let directWindowsPath = resolveWindowsPath(trimmed) {
            return directWindowsPath
        }

        if let installedProgram = programs.first(where: {
            $0.url.lastPathComponent.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return installedProgram.url
        }

        let candidates = candidateExecutableNames(for: trimmed)
        let searchRoots = [
            url.appending(path: "drive_c"),
            url.appending(path: "drive_c").appending(path: "windows"),
            url.appending(path: "drive_c").appending(path: "windows").appending(path: "system32")
        ]

        for root in searchRoots {
            for candidate in candidates {
                let candidateURL = root.appending(path: candidate)
                if let existing = existingFileURL(candidateURL) {
                    return existing
                }
            }
        }

        return nil
    }

    func commandPinSubtitle(_ pin: PinnedProgram) -> String {
        if let commandURL = resolveCommandURL(for: pin) {
            let commandPath = commandURL.path.hasPrefix(url.path(percentEncoded: false))
                ? commandURL.prettyPath(self)
                : commandURL.prettyPath()
            if pin.arguments.isEmpty {
                return commandPath
            }
            return "\(commandPath) \(pin.arguments)"
        }

        if pin.arguments.isEmpty {
            return pin.command
        }
        return "\(pin.command) \(pin.arguments)"
    }

    @MainActor
    func upsertCommandPin(id: UUID?, name: String, command: String, arguments: String) {
        var updatedSettings = settings
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedArguments = arguments.trimmingCharacters(in: .whitespacesAndNewlines)

        if let id, let index = updatedSettings.pins.firstIndex(where: { $0.id == id }) {
            updatedSettings.pins[index].name = normalizedName
            updatedSettings.pins[index].command = normalizedCommand
            updatedSettings.pins[index].arguments = normalizedArguments
            updatedSettings.pins[index].kind = .command
            updatedSettings.pins[index].url = nil
            updatedSettings.pins[index].removable = false
        } else {
            updatedSettings.pins.append(
                PinnedProgram(name: normalizedName, command: normalizedCommand, arguments: normalizedArguments)
            )
        }

        settings = updatedSettings
    }

    @MainActor
    func removePin(id: UUID) {
        var updatedSettings = settings
        updatedSettings.pins.removeAll(where: { $0.id == id })
        settings = updatedSettings
    }

    func revealCommandPin(_ pin: PinnedProgram) {
        guard let commandURL = resolveCommandURL(for: pin) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([commandURL])
    }
}

private extension Bottle {
    struct CommandPinWindowsUserInfo {
        let userProfile: String
        let homeDrive: String
        let homePath: String
        let userHomeURL: URL
    }

    func launchCommandPinConsole(arguments: String) async {
        do {
            Task.detached(priority: .userInitiated) {
                await Wine.ensureConsoleFont(bottle: self)
            }

            let userInfo = resolveCommandPinWindowsUserInfo()
            if !FileManager.default.fileExists(atPath: userInfo.userHomeURL.path) {
                try? FileManager.default.createDirectory(
                    at: userInfo.userHomeURL,
                    withIntermediateDirectories: true
                )
            }

            let startupCommand = normalizeConsoleStartupCommand(arguments)
            try await Wine.launchConsole(
                bottle: self,
                startupCommand: startupCommand,
                environment: [
                    "USERPROFILE": userInfo.userProfile,
                    "HOMEDRIVE": userInfo.homeDrive,
                    "HOMEPATH": userInfo.homePath,
                    "LANG": "zh_CN.UTF-8",
                    "LC_ALL": "zh_CN.UTF-8"
                ],
                directory: userInfo.userHomeURL
            )
            _ = await Wine.waitForProcessStart(
                bottle: self,
                imageName: "wineconsole.exe",
                timeoutSeconds: 2.5,
                pollIntervalSeconds: 0.2
            )
            await MainActor.run {
                Wine.centerWineFrontWindow()
            }
        } catch {
            await self.showCommandPinError(name: "cmd.exe", message: error.localizedDescription)
        }
    }

    func existingFileURL(_ candidate: URL) -> URL? {
        guard FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) else { return nil }
        return candidate
    }

    func resolveCommandPinWindowsUserInfo() -> CommandPinWindowsUserInfo {
        let usersDir = url
            .appending(path: "drive_c")
            .appending(path: "users")
        let reserved: Set<String> = [
            "Public",
            "Default",
            "Default User",
            "All Users"
        ]

        let userName: String = {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: usersDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return "crossover"
            }

            let directories = entries.filter { entry in
                (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            }
            if directories.contains(where: { $0.lastPathComponent == "crossover" }) {
                return "crossover"
            }
            let fallback = directories
                .map(\.lastPathComponent)
                .first(where: { !reserved.contains($0) })
            return fallback ?? "crossover"
        }()

        return CommandPinWindowsUserInfo(
            userProfile: #"C:\users\#(userName)"#,
            homeDrive: "C:",
            homePath: #"\\users\#(userName)"#,
            userHomeURL: usersDir.appending(path: userName)
        )
    }

    func resolveWindowsPath(_ command: String) -> URL? {
        let normalized = command.replacingOccurrences(of: "/", with: "\\")
        if normalized.hasPrefix("\\\\") {
            return nil
        }

        if normalized.count >= 3,
           normalized[normalized.index(normalized.startIndex, offsetBy: 1)] == ":",
           normalized[normalized.index(normalized.startIndex, offsetBy: 2)] == "\\" {
            let drive = String(normalized.prefix(1)).lowercased()
            guard let root = driveRoot(for: drive) else { return nil }
            let relative = String(normalized.dropFirst(3))
            let components = relative.split(separator: "\\").map(String.init)
            return existingFileURL(components.reduce(root) { partialResult, component in
                partialResult.appending(path: component)
            })
        }

        if normalized.contains("\\") {
            let components = normalized.split(separator: "\\").map(String.init)
            let root = url.appending(path: "drive_c")
            return existingFileURL(components.reduce(root) { partialResult, component in
                partialResult.appending(path: component)
            })
        }

        return nil
    }

    func driveRoot(for drive: String) -> URL? {
        let alias = url.appending(path: "dosdevices").appending(path: "\(drive):")
        if FileManager.default.fileExists(atPath: alias.path(percentEncoded: false)) {
            return URL(filePath: alias.path(percentEncoded: false)).resolvingSymlinksInPath()
        }
        if drive == "c" {
            return url.appending(path: "drive_c")
        }
        return nil
    }

    func candidateExecutableNames(for command: String) -> [String] {
        var names = [command]
        if !command.contains(".") {
            names.append(contentsOf: ["\(command).exe", "\(command).bat", "\(command).cmd"])
        }
        return names
    }

    func parseCommandArguments(_ arguments: String) -> [String] {
        var parsed: [String] = []
        var current = ""
        var activeQuote: Character?
        var escaping = false

        for character in arguments {
            if escaping {
                current.append(character)
                escaping = false
                continue
            }

            if character == "\\" && activeQuote != "'" {
                escaping = true
                continue
            }

            if character == "\"" || character == "'" {
                if activeQuote == character {
                    activeQuote = nil
                } else if activeQuote == nil {
                    activeQuote = character
                } else {
                    current.append(character)
                }
                continue
            }

            if character.isWhitespace && activeQuote == nil {
                if !current.isEmpty {
                    parsed.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                continue
            }

            current.append(character)
        }

        if escaping {
            current.append("\\")
        }

        if !current.isEmpty {
            parsed.append(current)
        }

        return parsed
    }

    func normalizeConsoleStartupCommand(_ arguments: String) -> String {
        var parts = parseCommandArguments(arguments)
        if let first = parts.first?.lowercased(), first == "/k" || first == "/c" {
            parts.removeFirst()
        }
        let command = parts.joined(separator: " ")
        if command.isEmpty {
            return "chcp 936>nul"
        }
        return "chcp 936>nul & \(command)"
    }

    @MainActor
    func showCommandPinError(name: String, message: String) {
        let alert = NSAlert()
        alert.messageText = "Failed to run command"
        alert.informativeText = "\(name): \(message)"
        alert.alertStyle = .critical
        alert.addButton(withTitle: String(localized: "button.ok"))
        alert.runModal()
    }
}
