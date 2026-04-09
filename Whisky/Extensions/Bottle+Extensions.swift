//
//  Bottle+Extensions.swift
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
import os.log

extension Bottle {
    func openCDrive() {
        NSWorkspace.shared.open(url.appending(path: "drive_c"))
    }

    func openTerminal() async {
        do {
            Task.detached(priority: .userInitiated) {
                await Wine.ensureConsoleFont(bottle: self)
            }
            let userInfo = resolveWindowsUserInfo()
            if !FileManager.default.fileExists(atPath: userInfo.userHomeURL.path) {
                try? FileManager.default.createDirectory(
                    at: userInfo.userHomeURL,
                    withIntermediateDirectories: true
                )
            }
            let startupCommand = "chcp 936>nul"
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
        } catch {
            await self.showRunError(message: error.localizedDescription)
        }
    }

    @discardableResult
    func getStartMenuPrograms() -> [Program] {
        let globalStartMenu = url
            .appending(path: "drive_c")
            .appending(path: "ProgramData")
            .appending(path: "Microsoft")
            .appending(path: "Windows")
            .appending(path: "Start Menu")

        let userStartMenu = url
            .appending(path: "drive_c")
            .appending(path: "users")
            .appending(path: "crossover")
            .appending(path: "AppData")
            .appending(path: "Roaming")
            .appending(path: "Microsoft")
            .appending(path: "Windows")
            .appending(path: "Start Menu")

        var startMenuPrograms: [Program] = []
        var linkURLs: [URL] = []
        let globalEnumerator = FileManager.default.enumerator(at: globalStartMenu,
                                                              includingPropertiesForKeys: [.isRegularFileKey],
                                                              options: [.skipsHiddenFiles])
        while let url = globalEnumerator?.nextObject() as? URL {
            if url.pathExtension == "lnk" {
                linkURLs.append(url)
            }
        }

        let userEnumerator = FileManager.default.enumerator(at: userStartMenu,
                                                            includingPropertiesForKeys: [.isRegularFileKey],
                                                            options: [.skipsHiddenFiles])
        while let url = userEnumerator?.nextObject() as? URL {
            if url.pathExtension == "lnk" {
                linkURLs.append(url)
            }
        }

        linkURLs.sort(by: { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() })

        for link in linkURLs {
            do {
                if let program = ShellLinkHeader.getProgram(url: link,
                                                            handle: try FileHandle(forReadingFrom: link),
                                                            bottle: self) {
                    if !startMenuPrograms.contains(where: { $0.url == program.url }) {
                        startMenuPrograms.append(program)
                        try FileManager.default.removeItem(at: link)
                    }
                }
            } catch {
                print(error)
            }
        }

        return startMenuPrograms
    }

    func updateInstalledPrograms() {
        let driveC = url.appending(path: "drive_c")
        var programs: [Program] = []
        var foundURLS: Set<URL> = []

        for folderName in ["Program Files", "Program Files (x86)"] {
            let folderURL = driveC.appending(path: folderName)
            let enumerator = FileManager.default.enumerator(
                at: folderURL, includingPropertiesForKeys: [.isExecutableKey], options: [.skipsHiddenFiles]
            )

            while let url = enumerator?.nextObject() as? URL {
                guard !url.hasDirectoryPath && url.pathExtension == "exe" else { continue }
                guard !settings.blocklist.contains(url) else { continue }
                foundURLS.insert(url)
                programs.append(Program(url: url, bottle: self))
            }
        }

        // Add missing programs from pins
        for pin in settings.pins {
            guard let url = pin.url else { continue }
            guard !foundURLS.contains(url) else { continue }
            programs.append(Program(url: url, bottle: self))
        }

        self.programs = programs.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    @MainActor
    func move(destination: URL) {
        do {
            if let bottle = BottleVM.shared.bottles.first(where: { $0.url == url }) {
                bottle.inFlight = true
                for index in 0..<bottle.settings.pins.count {
                    let pin = bottle.settings.pins[index]
                    if let url = pin.url {
                        bottle.settings.pins[index].url = url.updateParentBottle(old: url,
                                                                                 new: destination)
                    }
                }

                for index in 0..<bottle.settings.blocklist.count {
                    let blockedUrl = bottle.settings.blocklist[index]
                    bottle.settings.blocklist[index] = blockedUrl.updateParentBottle(old: url,
                                                                                     new: destination)
                }
            }
            try FileManager.default.moveItem(at: url, to: destination)
            if let path = BottleVM.shared.bottlesList.paths.firstIndex(of: url) {
                BottleVM.shared.bottlesList.paths[path] = destination
            }
            BottleVM.shared.loadBottles()
        } catch {
            print("Failed to move bottle")
        }
    }

    func exportAsArchive(destination: URL) {
        do {
            try Tar.tar(folder: url, toURL: destination)
        } catch {
            print("Failed to export bottle")
        }
    }

    @MainActor
    func remove(delete: Bool) {
        if let bottle = BottleVM.shared.bottles.first(where: { $0.url == url }) {
            bottle.inFlight = true
        }

        Task.detached(priority: .userInitiated) {
            do {
                if delete {
                    try FileManager.default.removeItem(at: self.url)
                }

                await MainActor.run {
                    if let path = BottleVM.shared.bottlesList.paths.firstIndex(of: self.url) {
                        BottleVM.shared.bottlesList.paths.remove(at: path)
                    }
                    BottleVM.shared.loadBottles()
                }
            } catch {
                await MainActor.run {
                    if let bottle = BottleVM.shared.bottles.first(where: { $0.url == self.url }) {
                        bottle.inFlight = false
                    }
                }
                print("Failed to remove bottle: \(error)")
            }
        }
    }

    @MainActor
    func rename(newName: String) {
        settings.name = newName
    }

    @MainActor private func showRunError(message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "alert.message")
        alert.informativeText = String(localized: "alert.info")
        + " \(self.url.lastPathComponent): "
        + message
        alert.alertStyle = .critical
        alert.addButton(withTitle: String(localized: "button.ok"))
        alert.runModal()
    }
}

private extension Bottle {
    struct WindowsUserInfo {
        let userName: String
        let userProfile: String
        let homeDrive: String
        let homePath: String
        let userHomeURL: URL
    }

    func resolveWindowsUserInfo() -> WindowsUserInfo {
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

            let directories = entries.filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            }
            if directories.contains(where: { $0.lastPathComponent == "crossover" }) {
                return "crossover"
            }
            let fallback = directories
                .map(\.lastPathComponent)
                .first(where: { !reserved.contains($0) })
            return fallback ?? "crossover"
        }()

        let homeDrive = "C:"
        let homePath = #"\\users\#(userName)"#
        let userProfile = #"C:\users\#(userName)"#
        let userHomeURL = usersDir.appending(path: userName)
        return WindowsUserInfo(
            userName: userName,
            userProfile: userProfile,
            homeDrive: homeDrive,
            homePath: homePath,
            userHomeURL: userHomeURL
        )
    }
}
