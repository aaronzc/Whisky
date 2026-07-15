//
//  CommandPinEditorView.swift
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
import UniformTypeIdentifiers
import WhiskyKit

struct CommandPinEditorView: View {
    let bottle: Bottle
    let pin: PinnedProgram?
    private let labelWidth: CGFloat = 84
    private let browseLabelWidth: CGFloat = 126
    private let fieldWidth: CGFloat = 300

    @State private var name: String
    @State private var command: String
    @State private var arguments: String

    @Environment(\.dismiss) private var dismiss

    init(bottle: Bottle, pin: PinnedProgram? = nil) {
        self.bottle = bottle
        self.pin = pin
        self._name = State(initialValue: pin?.name ?? "")
        self._command = State(initialValue: pin?.command ?? "")
        self._arguments = State(initialValue: pin?.arguments ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 0) {
                    labeledField("pin.name", text: $name)
                    Divider()
                    commandGroup
                    Divider()
                    labeledField("pin.command.arguments.label", text: $arguments)
                }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )

                if !previewPath.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("pin.command.preview")
                            .font(.headline)
                            .padding(.leading, 12)
                        Text(previewPath)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle(pin == nil ? "pin.command.createTitle" : "pin.command.editTitle")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("create.cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(pin == nil ? "pin.command.createButton" : "pin.command.saveButton") {
                        submit()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
                }
            }
            .onSubmit {
                submit()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: ViewWidth.small + 80)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var previewPath: String {
        let draft = PinnedProgram(
            name: name.isEmpty ? String(localized: "pin.command.defaultName") : name,
            command: command,
            arguments: arguments
        )
        return bottle.commandPinSubtitle(draft)
    }

    private func chooseCommandFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType.exe,
            UTType(exportedAs: "com.microsoft.bat")
        ]
        panel.directoryURL = bottle.url.appending(path: "drive_c")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.begin { result in
            guard result == .OK, let url = panel.urls.first else { return }
            command = url.path(percentEncoded: false)
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                name = url.deletingPathExtension().lastPathComponent
            }
        }
    }

    private var commandGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            labeledField("pin.command.label", text: $command)

            HStack(alignment: .center, spacing: 12) {
                Text("pin.command.pickExecutable")
                    .lineLimit(1)
                    .frame(width: browseLabelWidth, alignment: .leading)
                Spacer(minLength: 8)
                Button("create.browse") {
                    chooseCommandFile()
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 2)

            Text("pin.command.pickExecutable.subtitle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func submit() {
        Task { @MainActor in
            bottle.upsertCommandPin(
                id: pin?.id,
                name: name,
                command: command,
                arguments: arguments
            )
            dismiss()
        }
    }

    @ViewBuilder
    private func labeledField(_ titleKey: LocalizedStringKey, text: Binding<String>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(titleKey)
                .frame(width: labelWidth, alignment: .leading)
            Spacer(minLength: 0)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: fieldWidth)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

#Preview {
    CommandPinEditorView(bottle: Bottle(bottleUrl: URL(filePath: "")))
}
