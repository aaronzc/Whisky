//
//  CommandPinView.swift
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
import WhiskyKit

struct CommandPinView: View {
    @ObservedObject var bottle: Bottle
    @State var pin: PinnedProgram

    @State private var showEditor = false
    @State private var opening = false
    @State private var title: String = ""
    @State private var resolvedIcon: Image?

    var body: some View {
        VStack {
            Group {
                if let resolvedIcon {
                    resolvedIcon
                        .resizable()
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.95), Color.cyan.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(width: 45, height: 45)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                Text(">_")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                    )
                    .offset(x: 8, y: 8)
            }
            .scaleEffect(opening ? 1.95 : 1)
            .opacity(opening ? 0 : 1)

            Spacer()

            Text(title)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .help(bottle.commandPinSubtitle(pin))
        }
        .frame(width: 90, height: 90)
        .padding(10)
        .contextMenu {
            Button("button.run", systemImage: "play.fill") {
                runCommand()
            }
            .labelStyle(.titleAndIcon)

            Button("pin.command.editTitle", systemImage: "slider.horizontal.3") {
                showEditor = true
            }
            .labelStyle(.titleAndIcon)

            if bottle.resolveCommandURL(for: pin) != nil {
                Button("button.showInFinder", systemImage: "folder") {
                    bottle.revealCommandPin(pin)
                }
                .labelStyle(.titleAndIcon)
            }

            Divider()

            Button("button.remove", systemImage: "pin.slash") {
                Task { @MainActor in
                    bottle.removePin(id: pin.id)
                }
            }
            .labelStyle(.titleAndIcon)
        }
        .onTapGesture(count: 2) {
            runCommand()
        }
        .sheet(isPresented: $showEditor) {
            CommandPinEditorView(bottle: bottle, pin: pin)
        }
        .task {
            title = pin.name
            await loadResolvedIcon()
        }
        .onChange(of: bottle.settings) {
            if let updatedPin = bottle.settings.pins.first(where: { $0.id == pin.id }) {
                pin = updatedPin
                title = updatedPin.name
                Task {
                    await loadResolvedIcon()
                }
            }
        }
    }

    private func runCommand() {
        withAnimation(.easeIn(duration: 0.25)) {
            opening = true
        } completion: {
            withAnimation(.easeOut(duration: 0.1)) {
                opening = false
            }
        }

        bottle.runCommandPin(pin)
    }

    private func loadResolvedIcon() async {
        guard let commandURL = bottle.resolveCommandURL(for: pin) else {
            resolvedIcon = nil
            return
        }
        let task = Task.detached {
            guard let peFile = try? PEFile(url: commandURL),
                  let image = peFile.bestIcon() else { return nil as Image? }
            return Image(nsImage: image)
        }
        resolvedIcon = await task.value
    }
}

#Preview {
    CommandPinView(
        bottle: Bottle(bottleUrl: URL(filePath: "")),
        pin: PinnedProgram(name: "Terminal", command: "cmd.exe", arguments: "/k dir")
    )
}
