//
//  BottleView.swift
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

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import WhiskyKit

enum BottleStage {
    case config
    case programs
    case processes
}

struct BottleView: View {
    @ObservedObject var bottle: Bottle
    @State private var path = NavigationPath()
    @State private var programLoading: Bool = false
    @State private var showWinetricksSheet: Bool = false
    @State private var terminalLoading: Bool = false
    @State private var runPanelPresented: Bool = false

    private let gridLayout = [GridItem(.adaptive(minimum: 100, maximum: .infinity))]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVGrid(columns: gridLayout, alignment: .center) {
                    ForEach(bottle.pinnedPrograms, id: \.id) { pinnedProgram in
                        PinView(
                            bottle: bottle, program: pinnedProgram.program, pin: pinnedProgram.pin, path: $path
                        )
                    }
                    PinAddView(bottle: bottle)
                }
                .padding()
                Form {
                    NavigationLink(value: BottleStage.programs) {
                        Label("tab.programs", systemImage: "list.bullet")
                    }
                    NavigationLink(value: BottleStage.config) {
                        Label("tab.config", systemImage: "gearshape")
                    }
//                    NavigationLink(value: BottleStage.processes) {
//                        Label("tab.processes", systemImage: "hockey.puck.circle")
//                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
            }
            .bottomBar {
                HStack {
                    Spacer()
                    Button("button.cDrive") {
                        bottle.openCDrive()
                    }
                    Button {
                        guard !terminalLoading else { return }
                        terminalLoading = true
                        Task(priority: .userInitiated) {
                            let alreadyRunning = await Wine.isProcessRunning(
                                bottle: bottle,
                                imageName: "wineconsole.exe"
                            )
                            if alreadyRunning {
                                await MainActor.run {
                                    terminalLoading = false
                                }
                                Wine.activateWineApp()
                                return
                            }
                            await bottle.openTerminal()
                            let started = await Wine.waitForProcessStart(
                                bottle: bottle,
                                imageName: "wineconsole.exe",
                                timeoutSeconds: 1.5,
                                pollIntervalSeconds: 0.35
                            )
                            await MainActor.run {
                                terminalLoading = false
                            }
                            if started {
                                Wine.activateWineApp()
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("button.terminal")
                            if terminalLoading {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(terminalLoading)
                    Button("button.winetricks") {
                        showWinetricksSheet.toggle()
                    }
                    Button {
                        if runPanelPresented {
                            return
                        }
                        runPanelPresented = true
                        let panel = NSOpenPanel()
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = false
                        panel.canChooseFiles = true
                        panel.allowedContentTypes = [UTType.exe,
                                                     UTType(exportedAs: "com.microsoft.msi-installer"),
                                                     UTType(exportedAs: "com.microsoft.bat")]
                        panel.directoryURL = bottle.url.appending(path: "drive_c")
                        panel.begin { result in
                            programLoading = true
                            Task(priority: .userInitiated) {
                                await MainActor.run {
                                    runPanelPresented = false
                                }
                                if result == .OK {
                                    if let url = panel.urls.first {
                                        let imageName = url.lastPathComponent
                                        do {
                                            if url.pathExtension == "exe",
                                               await Wine.isProcessRunning(bottle: bottle, imageName: imageName) {
                                                await MainActor.run {
                                                    programLoading = false
                                                }
                                                Wine.activateWineApp()
                                                return
                                            }
                                            if url.pathExtension == "bat" {
                                                try await Wine.runBatchFile(url: url, bottle: bottle)
                                            } else {
                                                try await Wine.runProgram(at: url, bottle: bottle)
                                            }
                                        } catch {
                                            print("Failed to run external program: \(error)")
                                        }
                                        if url.pathExtension == "exe" {
                                            if await Wine.isProcessRunning(bottle: bottle,
                                                                           imageName: imageName) {
                                                Wine.activateWineApp()
                                            } else {
                                                _ = await Wine.waitForProcessStart(
                                                    bottle: bottle,
                                                    imageName: imageName
                                                )
                                            }
                                        }
                                        await MainActor.run {
                                            programLoading = false
                                        }
                                    }
                                } else {
                                    await MainActor.run {
                                        programLoading = false
                                    }
                                }
                                await MainActor.run {
                                    updateStartMenu()
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("button.run")
                            if programLoading {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(programLoading)
                }
                .padding()
            }
            .onAppear {
                updateStartMenu()
                Task.detached(priority: .userInitiated) {
                    await Wine.ensureDefaultFontSubstitutes(bottle: bottle)
                    await Wine.ensureConsoleFont(bottle: bottle)
                }
            }
            .disabled(!bottle.isAvailable)
            .navigationTitle(bottle.settings.name)
            .sheet(isPresented: $showWinetricksSheet) {
                WinetricksView(bottle: bottle)
            }
            .onChange(of: bottle.settings) { oldValue, newValue in
                guard oldValue != newValue else { return }
                // Trigger a reload
                BottleVM.shared.bottles = BottleVM.shared.bottles
            }
            .navigationDestination(for: BottleStage.self) { stage in
                switch stage {
                case .config:
                    ConfigView(bottle: bottle)
                case .programs:
                    ProgramsView(
                        bottle: bottle, path: $path
                    )
                case .processes:
                    RunningProcessesView(bottle: bottle)
                }
            }
            .navigationDestination(for: Program.self) { program in
                ProgramView(program: program)
            }
        }
    }

    private func updateStartMenu() {
        bottle.updateInstalledPrograms()

        let startMenuPrograms = bottle.getStartMenuPrograms()
        var programURLs = Set(bottle.programs.map { $0.url })
        for startMenuProgram in startMenuPrograms where !programURLs.contains(startMenuProgram.url) {
            bottle.programs.append(startMenuProgram)
            programURLs.insert(startMenuProgram.url)
        }
        bottle.programs = bottle.programs.sorted { $0.name.lowercased() < $1.name.lowercased() }

        var updatedSettings = bottle.settings
        for startMenuProgram in startMenuPrograms {
            for program in bottle.programs where
            // For some godforsaken reason "foo/bar" != "foo/Bar" so...
            program.url.path().caseInsensitiveCompare(startMenuProgram.url.path()) == .orderedSame {
                program.pinned = true
                guard !updatedSettings.pins.contains(where: { $0.url == program.url }) else { continue }
                updatedSettings.pins.append(PinnedProgram(
                    name: program.url.deletingPathExtension().lastPathComponent,
                    url: program.url
                ))
            }
        }
        bottle.settings = updatedSettings
    }
}

// Intentionally left empty; Wine windows are activated via Wine.activateWineApp().
