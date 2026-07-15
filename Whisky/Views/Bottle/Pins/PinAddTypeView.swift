//
//  PinAddTypeView.swift
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

enum PinAddDestination {
    case program
    case command
}

struct PinAddTypeView: View {
    let choose: (PinAddDestination) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                PinAddOptionCard(
                    title: "pin.add.program.title",
                    subtitle: "pin.add.program.subtitle",
                    systemImage: "rectangle.grid.2x2.fill",
                    accent: Color.orange
                ) {
                    choose(.program)
                }

                PinAddOptionCard(
                    title: "pin.add.command.title",
                    subtitle: "pin.add.command.subtitle",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    accent: Color.blue
                ) {
                    choose(.command)
                }
            }
            .padding(20)
            .navigationTitle("pin.add.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("create.cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
        .frame(minWidth: 420)
    }
}

private struct PinAddOptionCard: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                iconView

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(accent)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.regularMaterial)
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    @ViewBuilder
    private var iconView: some View {
        if systemImage == "rectangle.grid.2x2.fill" {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.98), Color.orange.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.18), lineWidth: 1)

                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.92), Color.orange.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 30, height: 34)
                    .overlay(alignment: .top) {
                        HStack(spacing: 3) {
                            Circle().frame(width: 3, height: 3)
                            Circle().frame(width: 3, height: 3)
                            Circle().frame(width: 3, height: 3)
                        }
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.top, 6)
                    }

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.orange)
                    .background(.white, in: Circle())
                    .offset(x: 13, y: 14)
            }
            .frame(width: 56, height: 56)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.95), accent.opacity(0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)
        }
    }
}

#Preview {
    PinAddTypeView { _ in }
}
