import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Main window: file table (or drop zone) on the left, rule stack on the right, action bar below.
struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("confirmBeforeRenaming") private var confirmBeforeRenaming = true
    @State private var selection = Set<FileItem.ID>()
    @State private var isTargeted = false
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                fileArea
                    .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                    .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
                RuleStackView()
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 480, maxHeight: .infinity)
            }
            Divider()
            bottomBar
        }
        .confirmationDialog("Rename \(model.changedCount) files?", isPresented: $confirming) {
            Button("Rename") { model.rename() }
        } message: {
            Text("You can undo this batch with Undo (⌘Z).")
        }
        .alert("Rename Failed", isPresented: Binding(get: { model.errorMessage != nil },
                                                     set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder private var fileArea: some View {
        if model.items.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Drop files here").font(.title2.weight(.medium))
                Text("Folders add the files inside them.").foregroundStyle(.secondary)
                Button("Choose Files…") { model.openPanel() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.5),
                                  style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            )
            .padding(20)
        } else {
            Table(model.items, selection: $selection) {
                TableColumn("Original") { item in
                    Text(item.original).lineLimit(1).truncationMode(.middle)
                }
                TableColumn("New name") { item in
                    HStack(spacing: 4) {
                        if item.status.problem != nil {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        }
                        Text(item.newName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(color(for: item.status))
                            .fontWeight(item.status == .changed ? .medium : .regular)
                    }
                    .help(item.status.problem ?? "")
                }
                TableColumn("Folder") { item in
                    Text(item.folder).lineLimit(1).truncationMode(.head).foregroundStyle(.secondary)
                }
            }
            .contextMenu(forSelectionType: FileItem.ID.self) { ids in
                Button("Reveal in Finder") {
                    let urls = model.items.filter { ids.contains($0.id) }.map(\.url)
                    NSWorkspace.shared.activateFileViewerSelecting(urls)
                }
                Button("Remove from List") { model.remove(ids) }
            }
            .onDeleteCommand { model.remove(selection); selection.removeAll() }
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 3).padding(2)
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button("Support / Donate ❤️") { AppLinks.openDonation() }
                .buttonStyle(.link)
            Divider().frame(height: 16)
            Text(summary).foregroundStyle(model.problemCount > 0 ? .red : .secondary)
            if model.isComputing { ProgressView().controlSize(.small) }
            Spacer()
            Button("Undo Last Batch") { model.undo() }
                .keyboardShortcut("z")
                .disabled(model.undoStack.isEmpty)
            Button("Rename") {
                if confirmBeforeRenaming { confirming = true } else { model.rename() }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(!model.canRename)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var summary: String {
        var parts = ["\(model.items.count) files", "\(model.changedCount) to rename"]
        if model.problemCount > 0 { parts.append("\(model.problemCount) conflicts") }
        if model.hasRuleErrors { parts.append("rule error") }
        return parts.joined(separator: " · ")
    }

    private func color(for status: RowStatus) -> Color {
        switch status {
        case .unchanged: return .secondary
        case .changed: return .primary
        case .collision, .invalid: return .red
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            accepted = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL else { return }
                Task { @MainActor in model.add([url]) }
            }
        }
        return accepted
    }
}
