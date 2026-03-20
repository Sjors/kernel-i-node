import SwiftUI

struct KernelLogSettingsView: View {
    @AppStorage(KernelLogSettings.loggingEnabledKey) private var loggingEnabled = true
    @AppStorage(KernelLogSettings.internalLogsEnabledKey) private var internalLogsEnabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Enable Kernel Logging", isOn: $loggingEnabled)
                    .onChange(of: loggingEnabled) { _, _ in
                        KernelLogSettings.notifyChanged()
                    }
                Toggle("Show Internal Kernel Logs", isOn: $internalLogsEnabled)
                    .disabled(!loggingEnabled)
                    .onChange(of: internalLogsEnabled) { _, _ in
                        KernelLogSettings.notifyChanged()
                    }
            } footer: {
                Text("The main toggle mutes all kernel logs without changing the category selections below.")
            }

            Section("Categories") {
                ForEach(KernelLogSettings.categories) { category in
                    KernelLogCategoryToggleRow(category: category, loggingEnabled: loggingEnabled)
                }
            }

            Section("Log Format") {
                KernelLogFormatToggleRow(title: "Timestamps", key: KernelLogSettings.logTimestampsKey, loggingEnabled: loggingEnabled)
                KernelLogFormatToggleRow(title: "Microsecond Precision", key: KernelLogSettings.logTimeMicrosKey, loggingEnabled: loggingEnabled)
                KernelLogFormatToggleRow(title: "Thread Names", key: KernelLogSettings.logThreadNamesKey, loggingEnabled: loggingEnabled)
                KernelLogFormatToggleRow(title: "Source Locations", key: KernelLogSettings.logSourceLocationsKey, loggingEnabled: loggingEnabled)
                KernelLogFormatToggleRow(title: "Category & Level", key: KernelLogSettings.alwaysPrintCategoryLevelsKey, loggingEnabled: loggingEnabled)
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 360, minHeight: 420)
        #endif
    }
}

private struct KernelLogCategoryToggleRow: View {
    let category: KernelLogCategorySetting
    let loggingEnabled: Bool
    @AppStorage private var isEnabled: Bool

    init(category: KernelLogCategorySetting, loggingEnabled: Bool) {
        self.category = category
        self.loggingEnabled = loggingEnabled
        _isEnabled = AppStorage(wrappedValue: false, category.preferenceKey)
    }

    var body: some View {
        Toggle(category.title, isOn: $isEnabled)
            .disabled(!loggingEnabled)
            .onChange(of: isEnabled) { _, _ in
                KernelLogSettings.notifyChanged()
            }
    }
}

private struct KernelLogFormatToggleRow: View {
    let title: String
    let key: String
    let loggingEnabled: Bool
    @AppStorage private var isEnabled: Bool

    init(title: String, key: String, loggingEnabled: Bool) {
        self.title = title
        self.key = key
        self.loggingEnabled = loggingEnabled
        _isEnabled = AppStorage(wrappedValue: false, key)
    }

    var body: some View {
        Toggle(title, isOn: $isEnabled)
            .disabled(!loggingEnabled)
            .onChange(of: isEnabled) { _, _ in
                KernelLogSettings.notifyChanged()
            }
    }
}

#Preview {
    KernelLogSettingsView()
}
