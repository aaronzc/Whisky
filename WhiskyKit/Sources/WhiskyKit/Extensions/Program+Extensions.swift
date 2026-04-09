//
//  Program+Extensions.swift
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
import os.log

private actor ProgramLaunchGuard {
    static let shared = ProgramLaunchGuard()
    private var launching: Set<URL> = []

    func acquire(_ url: URL) -> Bool {
        if launching.contains(url) {
            return false
        }
        launching.insert(url)
        return true
    }

    func release(_ url: URL) {
        launching.remove(url)
    }
}

private extension Program {
    var launchImageName: String {
        let lowercasedName = url.lastPathComponent.lowercased()
        if lowercasedName == "cmd.exe" {
            return "cmd.exe"
        }
        if lowercasedName == "powershell.exe" {
            return "powershell.exe"
        }
        return url.lastPathComponent
    }
}

extension Program {
    public func run() {
        if NSEvent.modifierFlags.contains(.shift) {
            self.runInTerminal()
        } else {
            Task.detached(priority: .userInitiated) {
                let acquired = await ProgramLaunchGuard.shared.acquire(self.url)
                if !acquired {
                    Wine.activateWineApp()
                    return
                }
                defer {
                    Task { await ProgramLaunchGuard.shared.release(self.url) }
                }

                let imageName = self.launchImageName
                if await Wine.isProcessRunning(bottle: self.bottle, imageName: imageName) {
                    Wine.activateWineApp()
                    return
                }

                await self.runInWine(imageName: imageName)
            }
        }
    }

    func runInWine(imageName: String) async {
        let arguments = settings.arguments.split { $0.isWhitespace }.map(String.init)
        let environment = generateEnvironment()

        do {
            if self.url.lastPathComponent.lowercased() == "cmd.exe" {
                await Wine.ensureConsoleFont(bottle: self.bottle)
                try await Wine.runProgram(
                    at: self.url, args: arguments, bottle: self.bottle, environment: environment
                )
            } else if self.url.lastPathComponent.lowercased() == "powershell.exe" {
                await Wine.ensureConsoleFont(bottle: self.bottle)
                let cmdURL = self.bottle.url
                    .appending(path: "drive_c")
                    .appending(path: "Windows")
                    .appending(path: "System32")
                    .appending(path: "cmd.exe")
                try await Wine.runProgram(
                    at: cmdURL,
                    args: ["/k", "powershell", "-NoExit", "-NoLogo"] + arguments,
                    bottle: self.bottle,
                    environment: environment
                )
            } else {
                try await Wine.runProgram(
                    at: self.url, args: arguments, bottle: self.bottle, environment: environment
                )
            }
            _ = await Wine.waitForProcessStart(bottle: self.bottle, imageName: imageName)
        } catch {
            await MainActor.run {
                self.showRunError(message: error.localizedDescription)
            }
        }
    }

    public func generateTerminalCommand() -> String {
        return Wine.generateRunCommand(
            at: self.url, bottle: bottle, args: settings.arguments, environment: generateEnvironment()
        )
    }

    public func runInTerminal() {
        let wineCmd = generateTerminalCommand().replacingOccurrences(of: "\\", with: "\\\\")

        let script = """
        tell application "Terminal"
            activate
            do script "\(wineCmd)"
        end tell
        """

        Task.detached(priority: .userInitiated) {
            var error: NSDictionary?
            guard let appleScript = NSAppleScript(source: script) else { return }
            appleScript.executeAndReturnError(&error)

            if let error = error {
                Logger.wineKit.error("Failed to run terminal script \(error)")
                guard let description = error["NSAppleScriptErrorMessage"] as? String else { return }
                await self.showRunError(message: String(describing: description))
            }
        }
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

// Intentionally left empty; Wine windows are activated via Wine.activateWineApp().
