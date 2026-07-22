import SwiftUI
import ScannerCore

struct ContentView: View {
    @StateObject private var model = ScannerViewModel()

    var body: some View {
        HStack(spacing: 0) {
            PagesArea(model: model)
                .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            OptionsPanel(model: model)
                .frame(width: 280)
        }
        .frame(minWidth: 800, minHeight: 560)
        .alert(
            L("error.title"),
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

// MARK: - Left side: scanned pages / empty state

private struct PagesArea: View {
    @ObservedObject var model: ScannerViewModel

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 16)]

    var body: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
            if model.pageItems.isEmpty {
                EmptyState(model: model)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(model.pageItems) { item in
                            VStack(spacing: 6) {
                                Image(nsImage: item.thumbnail)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .background(Color.white)
                                    .overlay(
                                        Rectangle().stroke(Color.black.opacity(0.15), lineWidth: 1)
                                    )
                                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                                Text(String(format: L("page.caption %d"), item.id))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
    }
}

private struct EmptyState: View {
    @ObservedObject var model: ScannerViewModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "scanner")
                .font(.system(size: 64, weight: .thin))
                .foregroundColor(.secondary)
            switch model.status {
            case .connected:
                Text(L("empty.title.ready")).font(.title2).fontWeight(.medium)
                Text(L("empty.subtitle.ready"))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            case .notFound:
                Text(L("empty.title.notfound")).font(.title2).fontWeight(.medium)
                Text(L("empty.subtitle.notfound"))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            case .searching:
                Text(L("status.searching"))
                    .foregroundColor(.secondary)
            }
        }
        .padding(40)
        .frame(maxWidth: 420)
    }
}

// MARK: - Right side: options panel

private struct OptionsPanel: View {
    @ObservedObject var model: ScannerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    statusRow
                    Divider()
                    settingsControls
                    Divider()
                    outputControls
                }
                .padding(16)
            }
            Spacer(minLength: 0)
            Divider()
            actionArea
                .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
            Text(statusText)
                .font(.callout)
                .lineLimit(2)
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .connected: return .green
        case .notFound: return .orange
        case .searching: return .gray
        }
    }

    private var statusText: String {
        switch model.status {
        case .connected(let name): return name
        case .notFound: return L("status.notfound")
        case .searching: return L("status.searching")
        }
    }

    @ViewBuilder
    private var settingsControls: some View {
        LabeledPicker(label: L("panel.kind"), selection: $model.mode) {
            Text(L("kind.color")).tag(ScanColorMode.color)
            Text(L("kind.gray")).tag(ScanColorMode.gray)
            Text(L("kind.bw")).tag(ScanColorMode.blackAndWhite)
        }

        LabeledPicker(label: L("panel.resolution"), selection: $model.resolution) {
            ForEach(model.availableResolutions, id: \.self) { dpi in
                Text("\(dpi) dpi").tag(dpi)
            }
        }

        LabeledPicker(label: L("panel.paper"), selection: $model.paperSize) {
            Text("A4").tag(PaperSize.a4)
            Text("A5").tag(PaperSize.a5)
            Text(L("paper.letter")).tag(PaperSize.letter)
            Text(L("paper.legal")).tag(PaperSize.legal)
        }

        Toggle(L("panel.duplex"), isOn: $model.duplex)
        Toggle(L("panel.deskew"), isOn: $model.deskew)
        Toggle(L("panel.skipblank"), isOn: $model.skipBlankPages)
    }

    @ViewBuilder
    private var outputControls: some View {
        LabeledPicker(label: L("panel.format"), selection: $model.format) {
            Text("PDF").tag(OutputFormat.pdf)
            Text(L("format.searchablePDF")).tag(OutputFormat.searchablePDF)
            Text("JPEG").tag(OutputFormat.jpeg)
            Text("PNG").tag(OutputFormat.png)
            Text("TIFF").tag(OutputFormat.tiff)
        }

        VStack(alignment: .leading, spacing: 4) {
            Text(L("panel.saveto")).font(.caption).foregroundColor(.secondary)
            Menu {
                folderButton(name: L("saveto.documents"), path: .documentDirectory)
                folderButton(name: L("saveto.desktop"), path: .desktopDirectory)
                folderButton(name: L("saveto.downloads"), path: .downloadsDirectory)
                Divider()
                Button(L("saveto.other")) { model.chooseSaveFolder() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text(model.saveFolder.lastPathComponent)
                        .lineLimit(1)
                }
            }
        }

        VStack(alignment: .leading, spacing: 4) {
            Text(L("panel.name")).font(.caption).foregroundColor(.secondary)
            TextField("", text: $model.fileName)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func folderButton(name: String, path: FileManager.SearchPathDirectory) -> some View {
        Button(name) {
            if let url = FileManager.default.urls(for: path, in: .userDomainMask).first {
                model.saveFolder = url
            }
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch model.activity {
            case .scanning(let page, let progress):
                ProgressView(value: progress) {
                    Text(String(format: L("progress.page %d"), page))
                        .font(.caption)
                }
                Button(L("button.cancel")) { model.cancelScan() }
                    .frame(maxWidth: .infinity)

            case .saving(let page, let total, let ocr):
                ProgressView(value: total > 0 ? Double(page) / Double(total) : 0) {
                    Text(ocr ? L("progress.ocr") : L("progress.saving"))
                        .font(.caption)
                }

            case .idle:
                if let saved = model.savedMessage {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(saved, systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.callout)
                            .lineLimit(2)
                        Button(L("button.showInFinder")) { model.showSavedInFinder() }
                            .font(.caption)
                    }
                }
                HStack {
                    if !model.pageItems.isEmpty {
                        Button(L("button.clear")) { model.clearPages() }
                    }
                    Spacer()
                    Button(L("button.scan")) { model.startScan() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!model.canScan)
                }
            }
        }
    }
}

// Small helper mirroring Image Capture's "label above control" style.
private struct LabeledPicker<SelectionValue: Hashable, Content: View>: View {
    let label: String
    let selection: Binding<SelectionValue>
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Picker("", selection: selection, content: content)
                .labelsHidden()
                .pickerStyle(.menu)
        }
    }
}
