import SwiftUI

/// Settings window: default date format, rename confirmation, and support link.
struct SettingsView: View {
    @AppStorage("defaultDateFormat") private var defaultDateFormat = "yyyy-MM-dd"
    @AppStorage("confirmBeforeRenaming") private var confirmBeforeRenaming = true

    var body: some View {
        Form {
            Section {
                TextField("Default date format", text: $defaultDateFormat)
                Text("Example: \(sample)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Confirm before renaming", isOn: $confirmBeforeRenaming)
            }
            Section {
                Button("Support / Donate ❤️") { AppLinks.openDonation() }
            } footer: {
                Text("BatchNameForge is free and open source.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }

    private var sample: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = defaultDateFormat
        return formatter.string(from: Date())
    }
}
