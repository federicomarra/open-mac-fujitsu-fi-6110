import AppKit
import ScannerCore
import SwiftUI

/// Preferences window: the default scan parameters applied at each launch.
/// Bound directly to UserDefaults via @AppStorage (same keys as `AppDefaults`).
struct SettingsView: View {
    @AppStorage(DefaultsKey.mode) private var mode = ScanColorMode.color.rawValue
    @AppStorage(DefaultsKey.resolution) private var resolution = 300
    @AppStorage(DefaultsKey.paperSize) private var paperSize = PaperSize.a4.rawValue
    @AppStorage(DefaultsKey.duplex) private var duplex = true
    @AppStorage(DefaultsKey.deskew) private var deskew = true
    @AppStorage(DefaultsKey.skipBlank) private var skipBlank = true
    @AppStorage(DefaultsKey.format) private var format = OutputFormat.pdf.rawValue
    @AppStorage(DefaultsKey.saveFolderPath) private var saveFolderPath = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("settings.header")).font(.headline)
                    Text(L("settings.subtitle"))
                        .font(.callout).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                section(L("settings.section.scan")) {
                    row(L("panel.kind")) {
                        Picker("", selection: $mode) {
                            Text(L("kind.color")).tag(ScanColorMode.color.rawValue)
                            Text(L("kind.gray")).tag(ScanColorMode.gray.rawValue)
                            Text(L("kind.bw")).tag(ScanColorMode.blackAndWhite.rawValue)
                        }.labelsHidden().frame(width: 170)
                    }
                    row(L("panel.resolution")) {
                        Picker("", selection: $resolution) {
                            ForEach(AppDefaults.resolutions, id: \.self) { Text("\($0) dpi").tag($0) }
                        }.labelsHidden().frame(width: 170)
                    }
                    row(L("panel.paper")) {
                        Picker("", selection: $paperSize) {
                            Text("A4").tag(PaperSize.a4.rawValue)
                            Text("A5").tag(PaperSize.a5.rawValue)
                            Text(L("paper.letter")).tag(PaperSize.letter.rawValue)
                            Text(L("paper.legal")).tag(PaperSize.legal.rawValue)
                        }.labelsHidden().frame(width: 170)
                    }
                    Toggle(L("panel.duplex"), isOn: $duplex)
                    Toggle(L("panel.deskew"), isOn: $deskew)
                    Toggle(L("panel.skipblank"), isOn: $skipBlank)
                }

                section(L("settings.section.output")) {
                    row(L("panel.format")) {
                        Picker("", selection: $format) {
                            Text("PDF").tag(OutputFormat.pdf.rawValue)
                            Text(L("format.searchablePDF")).tag(OutputFormat.searchablePDF.rawValue)
                            Text("JPEG").tag(OutputFormat.jpeg.rawValue)
                            Text("PNG").tag(OutputFormat.png.rawValue)
                            Text("TIFF").tag(OutputFormat.tiff.rawValue)
                        }.labelsHidden().frame(width: 170)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("settings.savefolder")).font(.caption).foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                            Text(saveFolderDisplayName).lineLimit(1)
                            Spacer()
                            if !saveFolderPath.isEmpty {
                                Button(L("settings.reset")) { saveFolderPath = "" }
                            }
                            Button(L("settings.choose")) { chooseFolder() }
                        }
                    }
                }
            }
            .padding(22)
        }
        .frame(width: 440)
    }

    private var saveFolderDisplayName: String {
        guard !saveFolderPath.isEmpty else { return L("saveto.documents") }
        let fm = FileManager.default
        let path = URL(fileURLWithPath: saveFolderPath).standardizedFileURL.path
        func matches(_ directory: FileManager.SearchPathDirectory) -> Bool {
            fm.urls(for: directory, in: .userDomainMask).first?.standardizedFileURL.path == path
        }
        if matches(.documentDirectory) { return L("saveto.documents") }
        if matches(.desktopDirectory) { return L("saveto.desktop") }
        if matches(.downloadsDirectory) { return L("saveto.downloads") }
        let name = fm.displayName(atPath: saveFolderPath)
        return name.isEmpty ? (saveFolderPath as NSString).lastPathComponent : name
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            saveFolderPath = url.path
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text(title).font(.subheadline).bold().foregroundColor(.secondary)
            content()
        }
    }

    @ViewBuilder
    private func row<Content: View>(_ label: String, @ViewBuilder _ control: () -> Content) -> some View {
        HStack {
            Text(label)
            Spacer()
            control()
        }
    }
}
