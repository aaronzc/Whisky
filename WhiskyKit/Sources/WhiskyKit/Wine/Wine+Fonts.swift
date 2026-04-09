//
//  Wine+Fonts.swift
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

// swiftlint:disable file_length

extension Wine {
    private actor FontInitCache {
        static let shared = FontInitCache()
        private var appliedBottlePaths: Set<String> = []

        func isApplied(bottle: Bottle) -> Bool {
            appliedBottlePaths.contains(bottle.url.path)
        }

        func markApplied(bottle: Bottle) {
            appliedBottlePaths.insert(bottle.url.path)
        }
    }

    private actor ConsoleFontInitCache {
        static let shared = ConsoleFontInitCache()
        private var appliedBottlePaths: Set<String> = []

        func isApplied(bottle: Bottle) -> Bool {
            appliedBottlePaths.contains(bottle.url.path)
        }

        func markApplied(bottle: Bottle) {
            appliedBottlePaths.insert(bottle.url.path)
        }
    }

    private enum FontRegistryKey {
        static let fontSubstitutes = #"HKLM\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes"#
        static let fonts = #"HKLM\Software\Microsoft\Windows NT\CurrentVersion\Fonts"#
        static let fontLink = #"HKLM\Software\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink"#
        static let consoleTrueType = #"HKLM\Software\Microsoft\Windows NT\CurrentVersion\Console\TrueTypeFont"#
        static let console = #"HKCU\Console"#
        static let whiskyFontsApplied = #"HKCU\Software\Whisky"#
        static let whiskyCommonApplied = #"HKCU\Software\Whisky"#
        static let macDriver = #"HKCU\Software\Wine\Mac Driver"#
        static let wineFontReplacements = #"HKCU\Software\Wine\Fonts\Replacements"#
        static let windowMetrics = #"HKCU\Control Panel\Desktop\WindowMetrics"#
        static let international = #"HKCU\Control Panel\International"#
        static let nlsCodePage = #"HKLM\SYSTEM\CurrentControlSet\Control\Nls\CodePage"#
    }

    public static func ensureDefaultFontSubstitutes(bottle: Bottle) async {
        if await FontInitCache.shared.isApplied(bottle: bottle) {
            return
        }
        do {
            let applied = try await Wine.queryRegistryKey(
                bottle: bottle, key: FontRegistryKey.whiskyFontsApplied,
                name: "FontsApplied", type: .string
            )
            let commonApplied = try await Wine.queryRegistryKey(
                bottle: bottle, key: FontRegistryKey.whiskyCommonApplied,
                name: "CommonApplied", type: .string
            )
            if applied == "1", commonApplied == "1" {
                await FontInitCache.shared.markApplied(bottle: bottle)
                return
            }

            let systemFontName = resolvePreferredFontNameFromSystemFonts(bottle: bottle)
            await applyCommonFontSettings(
                bottle: bottle,
                preferredFontName: systemFontName
            )
            if commonApplied != "1" {
                try? await Wine.addRegistryKey(
                    bottle: bottle, key: FontRegistryKey.whiskyCommonApplied, name: "CommonApplied",
                    data: "1", type: .string
                )
            }
            if applied == "1" {
                return
            }

            let preferredFontName = await resolvePreferredFontName(
                bottle: bottle,
                fontsAlreadyApplied: applied == "1"
            )
            await writeFontSubstitutes(bottle: bottle, preferredFontName: preferredFontName)
            await writeWindowMetricsFonts(bottle: bottle, fontName: systemFontName)
            if applied != "1" {
                try? await Wine.addRegistryKey(
                    bottle: bottle, key: FontRegistryKey.whiskyFontsApplied, name: "FontsApplied",
                    data: "1", type: .string
                )
            }
            await FontInitCache.shared.markApplied(bottle: bottle)
        } catch {
            return
        }
    }

    private static func ensureCJKFontAvailability(bottle: Bottle) async -> String? {
        let fontsDir = bottle.url.appending(path: "drive_c").appending(path: "windows").appending(path: "Fonts")
        do {
            try FileManager.default.createDirectory(at: fontsDir, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let installedFileNames = copyCJKFonts(into: fontsDir)
        guard let primaryFontFile = installedFileNames.first else {
            return nil
        }

        let preferredFaceName = preferredCJKFaceName(from: installedFileNames)
        let aliasFontFile = createWindowsFontAliases(
            fontsDir: fontsDir,
            primaryFontFile: primaryFontFile
        )
        let mappingFile = aliasFontFile ?? primaryFontFile
        await writeCJKFontMappings(bottle: bottle, fontFile: mappingFile)
        await writeCJKFontLinks(bottle: bottle,
                                installedFileNames: installedFileNames,
                                preferredFaceName: preferredFaceName,
                                linkFontFile: mappingFile)
        return preferredFaceName
    }

    private static func applyCommonFontSettings(
        bottle: Bottle,
        preferredFontName: String
    ) async {
        try? await Wine.addRegistryKey(
            bottle: bottle, key: FontRegistryKey.macDriver, name: "UseSystemFonts",
            data: "Y", type: .string
        )
        await ensureCJKLocale(bottle: bottle)
        await writeWineFontReplacements(bottle: bottle, preferredFontName: preferredFontName)
    }

    private static func resolvePreferredFontName(
        bottle: Bottle,
        fontsAlreadyApplied: Bool
    ) async -> String {
        if fontsAlreadyApplied {
            return resolvePreferredFontNameFromSystemFonts(bottle: bottle)
        }
        return await ensureCJKFontAvailability(bottle: bottle)
            ?? resolvePreferredFontNameFromSystemFonts(bottle: bottle)
    }

    private static func resolvePreferredFontNameFromSystemFonts(bottle: Bottle) -> String {
        let fontsDir = bottle.url.appending(path: "drive_c").appending(path: "windows").appending(path: "Fonts")
        if FileManager.default.fileExists(atPath: fontsDir.appending(path: "STHeiti Medium.ttc").path)
            || FileManager.default.fileExists(atPath: fontsDir.appending(path: "STHeiti Light.ttc").path) {
            return "Heiti SC"
        }
        if FileManager.default.fileExists(atPath: fontsDir.appending(path: "PingFang.ttc").path) {
            return "PingFang SC"
        }
        if FileManager.default.fileExists(atPath: fontsDir.appending(path: "Songti.ttc").path) {
            return "Songti SC"
        }
        return "SimSun"
    }

    private static func writeFontSubstitutes(
        bottle: Bottle,
        preferredFontName: String
    ) async {
        let substitutes: [String] = [
            "Segoe UI",
            "Segoe UI Symbol",
            "Segoe UI Emoji",
            "MS Shell Dlg",
            "MS Shell Dlg 2",
            "Microsoft Sans Serif",
            "MS Sans Serif",
            "Tahoma",
            "Arial",
            "Microsoft YaHei",
            "Microsoft YaHei UI",
            "SimSun",
            "SimSun-ExtB",
            "NSimSun",
            "SimHei",
            "MingLiU",
            "PMingLiU",
            "MS UI Gothic",
            "System",
            "Fixedsys"
        ]
        for name in substitutes {
            try? await Wine.addRegistryKey(
                bottle: bottle, key: FontRegistryKey.fontSubstitutes, name: name,
                data: preferredFontName, type: .string
            )
        }
    }

    private static func ensureCJKLocale(bottle: Bottle) async {
        let intlMappings: [(String, String)] = [
            ("Locale", "00000804"),
            ("LocaleName", "zh-CN"),
            ("iCountry", "86"),
            ("iLanguage", "0804"),
            ("sLanguage", "CHS"),
            ("sCountry", "China")
        ]
        for (name, value) in intlMappings {
            try? await Wine.addRegistryKey(
                bottle: bottle, key: FontRegistryKey.international, name: name,
                data: value, type: .string
            )
        }

        let codePageMappings: [(String, String)] = [
            ("ACP", "936"),
            ("OEMCP", "936"),
            ("MACCP", "10008")
        ]
        for (name, value) in codePageMappings {
            try? await Wine.addRegistryKey(
                bottle: bottle, key: FontRegistryKey.nlsCodePage, name: name,
                data: value, type: .string
            )
        }
    }

    private static func cjkFontCandidates() -> [String] {
        return [
            "/System/Library/Fonts/PingFang.ttc",
            "/System/Library/Fonts/Supplemental/PingFang.ttc",
            "/Library/Fonts/PingFang.ttc",
            "/System/Library/Fonts/Songti.ttc",
            "/System/Library/Fonts/Supplemental/Songti.ttc",
            "/System/Library/Fonts/STHeiti Medium.ttc",
            "/System/Library/Fonts/STHeiti Light.ttc",
            "/System/Library/Fonts/Supplemental/Heiti SC.ttf",
            "/System/Library/Fonts/Supplemental/Hiragino Sans GB.ttc"
        ]
    }

    private static func copyCJKFonts(into fontsDir: URL) -> [String] {
        var installedFileNames: [String] = []
        for candidatePath in cjkFontCandidates() {
            let sourceURL = URL(fileURLWithPath: candidatePath)
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                let destURL = fontsDir.appending(path: sourceURL.lastPathComponent)
                if !FileManager.default.fileExists(atPath: destURL.path) {
                    try? FileManager.default.copyItem(at: sourceURL, to: destURL)
                }
                installedFileNames.append(sourceURL.lastPathComponent)
            }
        }
        return installedFileNames
    }

    private static func preferredCJKFaceName(from installedFileNames: [String]) -> String {
        if installedFileNames.contains("STHeiti Medium.ttc")
            || installedFileNames.contains("STHeiti Light.ttc")
            || installedFileNames.contains("Heiti SC.ttf") {
            return "Heiti SC"
        }
        if installedFileNames.contains("PingFang.ttc") {
            return "PingFang SC"
        }
        if installedFileNames.contains("Songti.ttc") {
            return "Songti SC"
        }
        return "SimSun"
    }

    private static func writeCJKFontMappings(bottle: Bottle, fontFile: String) async {
        let mappings: [String] = [
            "SimSun (TrueType)",
            "NSimSun (TrueType)",
            "SimHei (TrueType)",
            "Microsoft YaHei (TrueType)",
            "Microsoft YaHei UI (TrueType)",
            "MS Shell Dlg (TrueType)",
            "MS Shell Dlg 2 (TrueType)",
            "Songti SC (TrueType)",
            "Heiti SC (TrueType)",
            "PingFang SC (TrueType)"
        ]

        for name in mappings {
            try? await Wine.addRegistryKey(
                bottle: bottle, key: FontRegistryKey.fonts, name: name,
                data: fontFile, type: .string
            )
        }

        let aliasMappings: [(String, String)] = [
            ("SimSun (TrueType)", "simsun.ttc"),
            ("NSimSun (TrueType)", "simsun.ttc"),
            ("SimHei (TrueType)", "simhei.ttf"),
            ("Microsoft YaHei (TrueType)", "msyh.ttf"),
            ("Microsoft YaHei UI (TrueType)", "msyh.ttf")
        ]
        for (name, file) in aliasMappings {
            try? await Wine.addRegistryKey(
                bottle: bottle, key: FontRegistryKey.fonts, name: name,
                data: file, type: .string
            )
        }
    }

    private static func writeCJKFontLinks(
        bottle: Bottle,
        installedFileNames: [String],
        preferredFaceName: String,
        linkFontFile: String
    ) async {
        let linkValue = "\(linkFontFile),\(preferredFaceName)"
        let linkTargets: [String] = [
            "MS Shell Dlg",
            "MS Shell Dlg 2",
            "Segoe UI",
            "Tahoma",
            "Arial"
        ]

        for name in linkTargets {
            try? await Wine.addRegistryKey(
                bottle: bottle, key: FontRegistryKey.fontLink, name: name,
                data: linkValue, type: .multiString
            )
        }
    }

    private static func createWindowsFontAliases(
        fontsDir: URL,
        primaryFontFile: String
    ) -> String? {
        let primaryURL = fontsDir.appending(path: primaryFontFile)
        guard FileManager.default.fileExists(atPath: primaryURL.path) else {
            return nil
        }

        let aliasFiles: [String] = [
            "simsun.ttc",
            "simsunb.ttf",
            "simhei.ttf",
            "msyh.ttf",
            "msyhbd.ttf"
        ]

        for alias in aliasFiles {
            let destURL = fontsDir.appending(path: alias)
            if !FileManager.default.fileExists(atPath: destURL.path) {
                try? FileManager.default.copyItem(at: primaryURL, to: destURL)
            }
        }

        return "simsun.ttc"
    }

    private static func writeWineFontReplacements(
        bottle: Bottle,
        preferredFontName: String
    ) async {
        let replacements: [String] = [
            "MS Shell Dlg",
            "MS Shell Dlg 2",
            "Segoe UI",
            "Tahoma",
            "Arial",
            "System",
            "Fixedsys",
            "Menu",
            "Small Fonts",
            "MS UI Gothic",
            "Helvetica"
        ]
        for name in replacements {
            try? await Wine.addRegistryKey(
                bottle: bottle, key: FontRegistryKey.wineFontReplacements, name: name,
                data: preferredFontName, type: .string
            )
        }
    }

    private static func writeWindowMetricsFonts(
        bottle: Bottle,
        fontName: String
    ) async {
        let valueHex = logFontHex(faceName: fontName, height: -12, weight: 400, charset: 134)
        let names: [String] = [
            "MenuFont",
            "StatusFont",
            "MessageFont",
            "IconFont",
            "CaptionFont",
            "SmCaptionFont"
        ]
        for name in names {
            try? await Wine.addRegistryKey(
                bottle: bottle,
                key: FontRegistryKey.windowMetrics,
                name: name,
                data: valueHex,
                type: .binary
            )
        }
    }

    private static func logFontHex(
        faceName: String,
        height: Int32,
        weight: Int32,
        charset: UInt8
    ) -> String {
        var bytes: [UInt8] = []

        func appendInt32(_ value: Int32) {
            let unsignedValue = UInt32(bitPattern: value)
            bytes.append(UInt8(truncatingIfNeeded: unsignedValue & 0xFF))
            bytes.append(UInt8(truncatingIfNeeded: (unsignedValue >> 8) & 0xFF))
            bytes.append(UInt8(truncatingIfNeeded: (unsignedValue >> 16) & 0xFF))
            bytes.append(UInt8(truncatingIfNeeded: (unsignedValue >> 24) & 0xFF))
        }

        appendInt32(height)        // lfHeight
        appendInt32(0)             // lfWidth
        appendInt32(0)             // lfEscapement
        appendInt32(0)             // lfOrientation
        appendInt32(weight)        // lfWeight
        bytes.append(0)            // lfItalic
        bytes.append(0)            // lfUnderline
        bytes.append(0)            // lfStrikeOut
        bytes.append(charset)      // lfCharSet (GB2312 = 134)
        bytes.append(0)            // lfOutPrecision
        bytes.append(0)            // lfClipPrecision
        bytes.append(0)            // lfQuality
        bytes.append(0)            // lfPitchAndFamily

        let utf16 = Array(faceName.utf16)
        for index in 0..<32 {
            let codeUnit: UInt16 = index < utf16.count ? utf16[index] : 0
            bytes.append(UInt8(truncatingIfNeeded: codeUnit & 0xFF))
            bytes.append(UInt8(truncatingIfNeeded: (codeUnit >> 8) & 0xFF))
        }

        return bytes.map { String(format: "%02X", $0) }.joined()
    }

    public static func ensureConsoleFont(bottle: Bottle) async {
        if await ConsoleFontInitCache.shared.isApplied(bottle: bottle) {
            return
        }
        do {
            await ensureConsoleFontFiles(bottle: bottle)
            try await applyConsoleFontDefaults(bottle: bottle)
            await ConsoleFontInitCache.shared.markApplied(bottle: bottle)
        } catch {
            return
        }
    }

    private static func applyConsoleFontDefaults(bottle: Bottle) async throws {
        let faceName = try await Wine.queryRegistryKey(
            bottle: bottle, key: FontRegistryKey.console, name: "FaceName", type: .string
        )
        if faceName != "Menlo" {
            try await Wine.addRegistryKey(
                bottle: bottle, key: FontRegistryKey.console, name: "FaceName",
                data: "Menlo", type: .string
            )
        }

        let fontFamily = try await Wine.queryRegistryKey(
            bottle: bottle, key: FontRegistryKey.console, name: "FontFamily", type: .dword
        )
        if fontFamily == nil {
            try await Wine.addRegistryKey(
                bottle: bottle, key: FontRegistryKey.console, name: "FontFamily",
                data: "54", type: .dword
            )
        }

        let fontWeight = try await Wine.queryRegistryKey(
            bottle: bottle, key: FontRegistryKey.console, name: "FontWeight", type: .dword
        )
        if fontWeight == nil {
            try await Wine.addRegistryKey(
                bottle: bottle, key: FontRegistryKey.console, name: "FontWeight",
                data: "400", type: .dword
            )
        }

        let fontSize = try await Wine.queryRegistryKey(
            bottle: bottle, key: FontRegistryKey.console, name: "FontSize", type: .dword
        )
        if fontSize == nil {
            // Height 12, Width 6 -> 0x000C0006
            try await Wine.addRegistryKey(
                bottle: bottle, key: FontRegistryKey.console, name: "FontSize",
                data: "786438", type: .dword
            )
        }

        let codePage = try await Wine.queryRegistryKey(
            bottle: bottle, key: FontRegistryKey.console, name: "CodePage", type: .dword
        )
        if codePage == nil {
            try await Wine.addRegistryKey(
                bottle: bottle, key: FontRegistryKey.console, name: "CodePage",
                data: "936", type: .dword
            )
        }
    }

    private static func ensureConsoleFontFiles(bottle: Bottle) async {
        let fontsDir = bottle.url.appending(path: "drive_c").appending(path: "windows").appending(path: "Fonts")
        do {
            try FileManager.default.createDirectory(at: fontsDir, withIntermediateDirectories: true)
        } catch {
            return
        }

        let menloCandidates: [String] = [
            "/System/Library/Fonts/Menlo.ttc",
            "/Library/Fonts/Menlo.ttc"
        ]

        var installedMenlo = false
        for path in menloCandidates {
            let sourceURL = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                let destURL = fontsDir.appending(path: "Menlo.ttc")
                if !FileManager.default.fileExists(atPath: destURL.path) {
                    try? FileManager.default.copyItem(at: sourceURL, to: destURL)
                }
                installedMenlo = true
                break
            }
        }

        if installedMenlo {
            try? await Wine.addRegistryKey(
                bottle: bottle, key: FontRegistryKey.fonts, name: "Consolas (TrueType)",
                data: "Menlo.ttc", type: .string
            )
            try? await Wine.addRegistryKey(
                bottle: bottle, key: FontRegistryKey.consoleTrueType, name: "0",
                data: "Consolas", type: .string
            )
        }
    }
}
