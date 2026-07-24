import Foundation
import ScannerCore

/// UserDefaults keys for the user's preferred default scan parameters.
enum DefaultsKey {
    static let mode = "defaultMode"
    static let resolution = "defaultResolution"
    static let paperSize = "defaultPaperSize"
    static let autoRotate = "defaultAutoRotate"
    static let duplex = "defaultDuplex"
    static let deskew = "defaultDeskew"
    static let skipBlank = "defaultSkipBlank"
    static let overwrite = "defaultOverwrite"
    static let format = "defaultFormat"
    static let saveFolderPath = "defaultSaveFolderPath"
}

/// The default scan parameters the app starts from at each launch. Editable in
/// the Settings window; seeded into `ScannerViewModel` on init. Factory values
/// (duplex + skip-blank on) are registered once at startup.
enum AppDefaults {
    static let resolutions = [150, 200, 300, 400, 600]

    static func registerFactory() {
        UserDefaults.standard.register(defaults: [
            DefaultsKey.mode: ScanColorMode.color.rawValue,
            DefaultsKey.resolution: 300,
            DefaultsKey.paperSize: PaperSize.a4.rawValue,
            // Auto-rotate leans on Apple Vision, which is fast on Apple Silicon
            // but slow on Intel — so it starts on only on Apple Silicon.
            DefaultsKey.autoRotate: isAppleSilicon,
            DefaultsKey.duplex: true,
            DefaultsKey.deskew: true,
            DefaultsKey.skipBlank: true,
            // Off by default: never silently replace an existing file — add a
            // "-1"/"-2" suffix instead.
            DefaultsKey.overwrite: false,
            DefaultsKey.format: OutputFormat.pdf.rawValue,
            DefaultsKey.saveFolderPath: "",
        ])
    }

    /// True on Apple Silicon hardware (also under Rosetta), false on Intel.
    static let isAppleSilicon: Bool = {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 else { return false }
        return value == 1
    }()

    private static var store: UserDefaults { .standard }

    static var mode: ScanColorMode {
        ScanColorMode(rawValue: store.string(forKey: DefaultsKey.mode) ?? "") ?? .color
    }
    static var resolution: Int {
        let value = store.integer(forKey: DefaultsKey.resolution)
        return resolutions.contains(value) ? value : 300
    }
    static var paperSize: PaperSize {
        PaperSize(rawValue: store.string(forKey: DefaultsKey.paperSize) ?? "") ?? .a4
    }
    static var autoRotate: Bool { store.bool(forKey: DefaultsKey.autoRotate) }
    static var duplex: Bool { store.bool(forKey: DefaultsKey.duplex) }
    static var deskew: Bool { store.bool(forKey: DefaultsKey.deskew) }
    static var skipBlank: Bool { store.bool(forKey: DefaultsKey.skipBlank) }
    static var overwrite: Bool { store.bool(forKey: DefaultsKey.overwrite) }
    static var format: OutputFormat {
        OutputFormat(rawValue: store.string(forKey: DefaultsKey.format) ?? "") ?? .pdf
    }

    /// Preferred save folder, falling back to ~/Documents when unset or missing.
    static var saveFolder: URL {
        let path = store.string(forKey: DefaultsKey.saveFolderPath) ?? ""
        if !path.isEmpty {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                return URL(fileURLWithPath: path)
            }
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }
}
