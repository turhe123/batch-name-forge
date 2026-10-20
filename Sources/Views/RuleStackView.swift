import SwiftUI

/// Right-hand panel: the ordered, reorderable list of rules plus the Add Rule menu.
struct RuleStackView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("defaultDateFormat") private var defaultDateFormat = "yyyy-MM-dd"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Rules").font(.headline)
                Spacer()
                Menu {
                    ForEach(RuleSpec.Kind.allCases) { kind in
                        Button {
                            model.addRule(kind, dateFormat: defaultDateFormat)
                        } label: {
                            Label(kind.title, systemImage: kind.symbol)
                        }
                    }
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
                .fixedSize()
            }
            .padding(12)
            Toggle("Include file extensions", isOn: $model.includeExtension)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            Divider()
            if model.rules.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle").font(.largeTitle).foregroundStyle(.tertiary)
                    Text("Add a rule to start renaming.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach($model.rules) { $rule in
                        RuleRow(rule: $rule) { model.removeRule(rule.id) }
                    }
                    .onMove { model.rules.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.inset)
            }
        }
    }
}

/// One rule in the stack: enable toggle, title, remove button and an expandable editor.
struct RuleRow: View {
    @Binding var rule: RuleSpec
    let onRemove: () -> Void
    @State private var expanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                editor
                if let error = rule.validationError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
            .disabled(!rule.enabled)
        } label: {
            HStack {
                Toggle("", isOn: $rule.enabled).labelsHidden().help("Enable or disable this rule")
                Image(systemName: rule.kind.symbol).frame(width: 18)
                Text(rule.kind.title).foregroundStyle(rule.enabled ? .primary : .secondary)
                Spacer()
                Button(action: onRemove) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove rule")
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var editor: some View {
        switch rule.kind {
        case .findReplace:
            TextField("Find", text: $rule.find)
            TextField("Replace with", text: $rule.replace)
            HStack {
                Toggle("Regular expression", isOn: $rule.useRegex)
                Toggle("Match case", isOn: $rule.caseSensitive)
            }
            if rule.useRegex {
                Text("Use $1, $2… in the replacement for capture groups.").font(.caption).foregroundStyle(.secondary)
            }
        case .addText:
            TextField("Text", text: $rule.text)
            positionPicker
        case .removeChars:
            Picker("Remove", selection: $rule.removeMode) {
                ForEach(RemoveCharsRule.Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            if rule.removeMode == .characters {
                TextField("Characters to remove", text: $rule.text)
            } else {
                Stepper("Count: \(rule.count)", value: $rule.count, in: 0...255)
            }
        case .changeCase:
            Picker("Case", selection: $rule.caseStyle) {
                ForEach(CaseRule.Style.allCases) { Text($0.rawValue).tag($0) }
            }
        case .sequence:
            Stepper("Start: \(rule.start)", value: $rule.start, in: -99_999...999_999)
            Stepper("Step: \(rule.step)", value: $rule.step, in: -1000...1000)
            Stepper("Padding: \(rule.padding) digits", value: $rule.padding, in: 1...10)
            TextField("Separator", text: $rule.separator)
            positionPicker
        case .modifiedDate, .createdDate, .exifDate:
            TextField("Date format (e.g. yyyy-MM-dd)", text: $rule.dateFormat)
            TextField("Separator", text: $rule.separator)
            positionPicker
            if rule.kind == .exifDate {
                Text("Files without capture metadata are left unchanged.").font(.caption).foregroundStyle(.secondary)
            }
        case .trim:
            Toggle("Collapse repeated spaces", isOn: $rule.collapseSpaces)
        }
    }

    private var positionPicker: some View {
        Picker("Position", selection: $rule.position) {
            ForEach(InsertPosition.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }
}
