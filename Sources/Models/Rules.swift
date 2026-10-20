import Foundation

/// Per-file information a rule may need while computing a new name.
struct RuleContext {
    let index: Int
    let url: URL
    let metadata: MetadataCache
}

/// One renaming step: maps a name and the file's position in the batch to a new name.
protocol RenameRule {
    func apply(to name: String, context: RuleContext) -> String
}

/// Where inserted text goes relative to the existing name.
enum InsertPosition: String, Codable, CaseIterable, Identifiable {
    case prefix = "Prefix", suffix = "Suffix"
    var id: String { rawValue }

    func insert(_ text: String, into name: String, separator: String = "") -> String {
        self == .prefix ? text + separator + name : name + separator + text
    }
}

/// Find and replace, either literal or regular-expression based.
struct FindReplaceRule: RenameRule {
    let find: String
    let replace: String
    let regex: NSRegularExpression?
    let caseSensitive: Bool

    func apply(to name: String, context: RuleContext) -> String {
        guard !find.isEmpty else { return name }
        if let regex {
            return regex.stringByReplacingMatches(in: name, range: NSRange(name.startIndex..., in: name), withTemplate: replace)
        }
        return name.replacingOccurrences(of: find, with: replace, options: caseSensitive ? [] : [.caseInsensitive])
    }
}

/// Adds fixed text before or after the name.
struct AddTextRule: RenameRule {
    let text: String
    let position: InsertPosition
    func apply(to name: String, context: RuleContext) -> String { position.insert(text, into: name) }
}

/// Removes a set of characters, or a number of characters from the start or end.
struct RemoveCharsRule: RenameRule {
    enum Mode: String, Codable, CaseIterable, Identifiable {
        case characters = "Characters", first = "First N", last = "Last N"
        var id: String { rawValue }
    }
    let mode: Mode
    let characters: String
    let count: Int

    func apply(to name: String, context: RuleContext) -> String {
        switch mode {
        case .characters: return String(name.filter { !characters.contains($0) })
        case .first: return String(name.dropFirst(max(0, count)))
        case .last: return String(name.dropLast(max(0, count)))
        }
    }
}

/// Changes letter case.
struct CaseRule: RenameRule {
    enum Style: String, Codable, CaseIterable, Identifiable {
        case lower = "lowercase", upper = "UPPERCASE", title = "Title Case", sentence = "Sentence case"
        var id: String { rawValue }
    }
    let style: Style

    func apply(to name: String, context: RuleContext) -> String {
        switch style {
        case .lower: return name.lowercased()
        case .upper: return name.uppercased()
        case .title: return name.capitalized
        case .sentence: return name.prefix(1).uppercased() + name.dropFirst().lowercased()
        }
    }
}

/// Adds a zero-padded sequence number derived from the row index.
struct SequenceRule: RenameRule {
    let start: Int, step: Int, padding: Int
    let separator: String
    let position: InsertPosition

    func apply(to name: String, context: RuleContext) -> String {
        let value = start + context.index * step
        var digits = String(abs(value))
        if digits.count < padding { digits = String(repeating: "0", count: padding - digits.count) + digits }
        return position.insert((value < 0 ? "-" : "") + digits, into: name, separator: separator)
    }
}

/// Inserts a file date (modified, created or EXIF capture) formatted with a user pattern.
struct DateRule: RenameRule {
    let source: DateSource
    let formatter: DateFormatter
    let separator: String
    let position: InsertPosition

    func apply(to name: String, context: RuleContext) -> String {
        guard let date = context.metadata.date(source, for: context.url) else { return name }
        return position.insert(formatter.string(from: date), into: name, separator: separator)
    }
}

/// Trims leading/trailing whitespace and optionally collapses repeated spaces.
struct TrimRule: RenameRule {
    let collapse: Bool
    func apply(to name: String, context: RuleContext) -> String {
        var result = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if collapse {
            result = result.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        }
        return result
    }
}

/// Editable, persistable description of a rule in the stack; builds the concrete `RenameRule`.
struct RuleSpec: Identifiable, Codable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case findReplace, addText, removeChars, changeCase, sequence, modifiedDate, createdDate, exifDate, trim
        var id: String { rawValue }

        var title: String {
            switch self {
            case .findReplace: return "Find & Replace"
            case .addText: return "Add Prefix / Suffix"
            case .removeChars: return "Remove Characters"
            case .changeCase: return "Change Case"
            case .sequence: return "Sequence Number"
            case .modifiedDate: return "Modification Date"
            case .createdDate: return "Creation Date"
            case .exifDate: return "Capture Date (EXIF)"
            case .trim: return "Trim Whitespace"
            }
        }

        var symbol: String {
            switch self {
            case .findReplace: return "magnifyingglass"
            case .addText: return "text.insert"
            case .removeChars: return "delete.left"
            case .changeCase: return "textformat"
            case .sequence: return "number"
            case .modifiedDate, .createdDate: return "calendar"
            case .exifDate: return "camera"
            case .trim: return "scissors"
            }
        }
    }

    var id = UUID()
    var kind: Kind
    var enabled = true
    var find = ""
    var replace = ""
    var useRegex = false
    var caseSensitive = true
    var text = ""
    var position: InsertPosition = .prefix
    var removeMode: RemoveCharsRule.Mode = .characters
    var count = 1
    var caseStyle: CaseRule.Style = .lower
    var start = 1
    var step = 1
    var padding = 3
    var separator = "_"
    var dateFormat = "yyyy-MM-dd"
    var collapseSpaces = true

    /// Human-readable problem with the current configuration, shown inline in the editor.
    var validationError: String? {
        switch kind {
        case .findReplace where useRegex && !find.isEmpty:
            do { _ = try NSRegularExpression(pattern: find) } catch {
                return "Invalid regular expression: \((error as NSError).localizedDescription)"
            }
        case .modifiedDate, .createdDate, .exifDate:
            if dateFormat.trimmingCharacters(in: .whitespaces).isEmpty { return "Date format is empty" }
        default: break
        }
        return nil
    }

    /// Builds the concrete rule, or nil if the configuration is invalid.
    func makeRule() -> RenameRule? {
        guard validationError == nil else { return nil }
        switch kind {
        case .findReplace:
            let regex = useRegex && !find.isEmpty
                ? try? NSRegularExpression(pattern: find, options: caseSensitive ? [] : [.caseInsensitive]) : nil
            return FindReplaceRule(find: find, replace: replace, regex: regex, caseSensitive: caseSensitive)
        case .addText: return AddTextRule(text: text, position: position)
        case .removeChars: return RemoveCharsRule(mode: removeMode, characters: text, count: count)
        case .changeCase: return CaseRule(style: caseStyle)
        case .sequence:
            return SequenceRule(start: start, step: step, padding: padding, separator: separator, position: position)
        case .modifiedDate, .createdDate, .exifDate:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = dateFormat
            let source: DateSource = kind == .modifiedDate ? .modified : (kind == .createdDate ? .created : .capture)
            return DateRule(source: source, formatter: formatter, separator: separator, position: position)
        case .trim: return TrimRule(collapse: collapseSpaces)
        }
    }
}

/// A named, saved rule stack.
struct Preset: Codable, Identifiable, Equatable {
    var name: String
    var rules: [RuleSpec]
    var includeExtension: Bool
    var id: String { name }
}
