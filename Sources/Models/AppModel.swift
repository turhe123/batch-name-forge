import AppKit
import Foundation

/// A file in the list together with its live preview result.
struct FileItem: Identifiable, Hashable {
    let id = UUID()
    var url: URL
    var newName: String
    var status: RowStatus = .unchanged

    var original: String { url.lastPathComponent }
    var folder: String { (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath }
}

/// Lock-protected counter so the background preview queue can skip stale requests.
final class LatestGeneration: @unchecked Sendable {
    private var value = 0
    private let lock = NSLock()
    func set(_ v: Int) { lock.lock(); value = v; lock.unlock() }
    func get() -> Int { lock.lock(); defer { lock.unlock() }; return value }
}

/// Central app state: file list, rule stack, background preview, rename/undo and presets.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var items: [FileItem] = []
    @Published var rules: [RuleSpec] = [] { didSet { if rules != oldValue { refresh() } } }
    @Published var includeExtension = false { didSet { if includeExtension != oldValue { refresh() } } }
    @Published private(set) var undoStack: [[RenameEngine.Move]] = []
    @Published private(set) var isComputing = false
    @Published private(set) var presets: [Preset] = PresetStore.load()
    @Published var errorMessage: String?

    private let cache = MetadataCache()
    private var generation = 0
    private let latest = LatestGeneration()
    private let previewQueue = DispatchQueue(label: "BatchNameForge.preview", qos: .userInitiated)

    var changedCount: Int { items.filter { $0.status == .changed }.count }
    var problemCount: Int { items.filter { $0.status.problem != nil }.count }
    var hasRuleErrors: Bool { rules.contains { $0.enabled && $0.validationError != nil } }
    var canRename: Bool { !isComputing && changedCount > 0 && problemCount == 0 && !hasRuleErrors }

    // MARK: Files

    func add(_ urls: [URL]) {
        let fm = FileManager.default
        var expanded: [URL] = []
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            if values?.isDirectory == true, values?.isPackage != true,
               let children = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                expanded += children.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            } else {
                expanded.append(url)
            }
        }
        var known = Set(items.map { $0.url.standardizedFileURL.path })
        for url in expanded where known.insert(url.standardizedFileURL.path).inserted {
            items.append(FileItem(url: url.standardizedFileURL, newName: url.lastPathComponent))
        }
        refresh()
    }

    func remove(_ ids: Set<FileItem.ID>) {
        items.removeAll { ids.contains($0.id) }
        refresh()
    }

    func clear() {
        items.removeAll()
        refresh()
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose files to rename. Choosing a folder adds the files inside it."
        if panel.runModal() == .OK { add(panel.urls) }
    }

    // MARK: Rules

    func addRule(_ kind: RuleSpec.Kind, dateFormat: String) {
        var rule = RuleSpec(kind: kind)
        rule.dateFormat = dateFormat
        if kind == .addText || kind == .removeChars { rule.text = "" }
        if [.modifiedDate, .createdDate, .exifDate].contains(kind) { rule.separator = " " }
        rules.append(rule)
    }

    func removeRule(_ id: RuleSpec.ID) { rules.removeAll { $0.id == id } }

    // MARK: Preview

    /// Recomputes the preview off the main thread; stale results are discarded via a generation counter.
    func refresh() {
        generation += 1
        let gen = generation
        let urls = items.map(\.url)
        let rules = rules
        let includeExtension = includeExtension
        let cache = cache
        let latest = latest
        latest.set(gen)
        isComputing = true
        previewQueue.async { [weak self] in
            // Skip passes superseded while queued (e.g. fast typing in a rule field).
            guard latest.get() == gen else { return }
            let results = RenameEngine.preview(urls: urls, rules: rules, includeExtension: includeExtension, cache: cache)
            Task { @MainActor in
                guard let self, gen == self.generation, results.count == self.items.count else { return }
                var updated = self.items
                for i in updated.indices {
                    updated[i].newName = results[i].0
                    updated[i].status = results[i].1
                }
                self.items = updated
                self.isComputing = false
            }
        }
    }

    // MARK: Rename & Undo

    func rename() {
        guard canRename else { return }
        let moves = items.filter { $0.status == .changed }.map {
            RenameEngine.Move(from: $0.url, to: $0.url.deletingLastPathComponent().appendingPathComponent($0.newName))
        }
        do {
            try RenameEngine.perform(moves)
            undoStack.append(moves)
            apply(moves)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func undo() {
        guard let last = undoStack.last else { return }
        let reversed = last.map { RenameEngine.Move(from: $0.to, to: $0.from) }
        do {
            try RenameEngine.perform(reversed)
            undoStack.removeLast()
            apply(reversed)
        } catch {
            errorMessage = "Undo failed. " + error.localizedDescription
        }
    }

    private func apply(_ moves: [RenameEngine.Move]) {
        let map = Dictionary(moves.map { ($0.from, $0.to) }, uniquingKeysWith: { a, _ in a })
        items = items.map { item in
            guard let to = map[item.url] else { return item }
            return FileItem(url: to, newName: to.lastPathComponent)
        }
        refresh()
    }

    // MARK: Presets

    func savePreset() {
        let alert = NSAlert()
        alert.messageText = "Save Preset"
        alert.informativeText = "Name this rule stack. An existing preset with the same name is replaced."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Preset name"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        var updated = presets.filter { $0.name != name }
        updated.append(Preset(name: name, rules: rules, includeExtension: includeExtension))
        updated.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        persist(updated)
    }

    func load(_ preset: Preset) {
        includeExtension = preset.includeExtension
        rules = preset.rules.map { var r = $0; r.id = UUID(); return r }
    }

    func delete(_ preset: Preset) { persist(presets.filter { $0.name != preset.name }) }

    private func persist(_ updated: [Preset]) {
        do {
            try PresetStore.save(updated)
            presets = updated
        } catch {
            errorMessage = "Couldn’t save presets: \(error.localizedDescription)"
        }
    }
}
