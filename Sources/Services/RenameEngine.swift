import Foundation

/// Preview state of a single row.
enum RowStatus: Hashable {
    case unchanged, changed
    case collision(String)
    case invalid(String)

    var problem: String? {
        switch self {
        case .collision(let msg), .invalid(let msg): return msg
        default: return nil
        }
    }
}

/// A rename that failed partway; everything already moved was rolled back.
struct RenameFailure: LocalizedError {
    let file: String
    let reason: String
    var errorDescription: String? {
        "Couldn’t rename “\(file)”: \(reason)\nAll files already renamed in this batch were restored."
    }
}

/// Pure name computation, collision detection, and the two-phase transactional rename.
enum RenameEngine {
    struct Move: Hashable { let from: URL; let to: URL }

    /// Computes the proposed name and status for every URL.
    static func preview(urls: [URL], rules: [RuleSpec], includeExtension: Bool, cache: MetadataCache) -> [(String, RowStatus)] {
        let compiled = rules.filter(\.enabled).compactMap { $0.makeRule() }
        var results: [(String, RowStatus)] = urls.enumerated().map { index, url in
            let original = url.lastPathComponent
            let ext = includeExtension ? "" : url.pathExtension
            var stem = ext.isEmpty ? original : String(original.dropLast(ext.count + 1))
            let context = RuleContext(index: index, url: url, metadata: cache)
            for rule in compiled { stem = rule.apply(to: stem, context: context) }
            stem = sanitize(stem)
            let name = ext.isEmpty ? stem : stem + "." + ext
            if stem.isEmpty || name == "." || name == ".." { return (name, .invalid("Name would be empty")) }
            if name.utf8.count > 255 { return (name, .invalid("Name is longer than 255 bytes")) }
            return (name, name == original ? .unchanged : .changed)
        }

        // Collision detection is case-insensitive to match default APFS/HFS+ volumes.
        let targets = zip(urls, results).map { $0.deletingLastPathComponent().appendingPathComponent($1.0).path.lowercased() }
        let sources = Set(urls.map { $0.path.lowercased() })
        var counts: [String: Int] = [:]
        for t in targets { counts[t, default: 0] += 1 }
        let fm = FileManager.default
        for i in results.indices where results[i].1 == .changed || results[i].1 == .unchanged {
            if counts[targets[i], default: 0] > 1 {
                results[i].1 = .collision("Another file in the batch gets the same name")
            } else if results[i].1 == .changed, !sources.contains(targets[i]),
                      fm.fileExists(atPath: urls[i].deletingLastPathComponent().appendingPathComponent(results[i].0).path) {
                results[i].1 = .collision("A file with this name already exists in the folder")
            }
        }
        return results
    }

    /// Replaces characters that are illegal or troublesome in macOS file names.
    static func sanitize(_ name: String) -> String {
        String(name.map { $0 == "/" || $0 == ":" ? "-" : $0 }.filter { !$0.isASCII || $0.asciiValue.map { $0 >= 32 } == true })
    }

    /// Moves every file to a temporary name, then to its final name, so swaps and chains never collide.
    /// On any failure, all completed moves are reversed before throwing.
    static func perform(_ moves: [Move]) throws {
        let fm = FileManager.default
        var done: [Move] = []
        func rollback() {
            for m in done.reversed() { try? fm.moveItem(at: m.to, to: m.from) }
        }
        var staged: [(temp: URL, move: Move)] = []
        for m in moves {
            let temp = m.from.deletingLastPathComponent().appendingPathComponent(".bnf-\(UUID().uuidString)")
            do {
                try fm.moveItem(at: m.from, to: temp)
                done.append(Move(from: m.from, to: temp))
                staged.append((temp, m))
            } catch {
                rollback()
                throw RenameFailure(file: m.from.lastPathComponent, reason: error.localizedDescription)
            }
        }
        for (temp, m) in staged {
            do {
                if fm.fileExists(atPath: m.to.path) {
                    throw CocoaError(.fileWriteFileExists)
                }
                try fm.moveItem(at: temp, to: m.to)
                done.append(Move(from: temp, to: m.to))
            } catch {
                rollback()
                throw RenameFailure(file: m.from.lastPathComponent, reason: error.localizedDescription)
            }
        }
    }
}
