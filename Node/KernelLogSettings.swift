import Foundation

struct KernelLogCategorySetting: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let preferenceKey: String
    let kernelCategory: UInt8
}

struct KernelLogSettingsSnapshot: Equatable, Sendable {
    let isEnabled: Bool
    let internalLogsEnabled: Bool
    let enabledCategories: [UInt8]
    let logTimestamps: Bool
    let logTimeMicros: Bool
    let logThreadNames: Bool
    let logSourceLocations: Bool
    let alwaysPrintCategoryLevels: Bool
}

enum KernelLogSettings {
    static let loggingEnabledKey = "kernel_logging_enabled"
    static let internalLogsEnabledKey = "kernel_internal_logs_enabled"
    static let kernelLogCategoryValidation: UInt8 = 9
    static let kernelLogCategoryKernel: UInt8 = 10
    static let logTimestampsKey = "kernel_log_format_timestamps"
    static let logTimeMicrosKey = "kernel_log_format_time_micros"
    static let logThreadNamesKey = "kernel_log_format_threadnames"
    static let logSourceLocationsKey = "kernel_log_format_sourcelocations"
    static let alwaysPrintCategoryLevelsKey = "kernel_log_format_category_levels"
    static let didChangeNotification = Notification.Name("KernelLogSettingsDidChange")

    static let categories: [KernelLogCategorySetting] = [
        KernelLogCategorySetting(id: "bench", title: "Bench", preferenceKey: "kernel_log_category_bench", kernelCategory: 1),
        KernelLogCategorySetting(id: "blockstorage", title: "Block Storage", preferenceKey: "kernel_log_category_blockstorage", kernelCategory: 2),
        KernelLogCategorySetting(id: "coindb", title: "CoinDB", preferenceKey: "kernel_log_category_coindb", kernelCategory: 3),
        KernelLogCategorySetting(id: "leveldb", title: "LevelDB", preferenceKey: "kernel_log_category_leveldb", kernelCategory: 4),
        KernelLogCategorySetting(id: "mempool", title: "Mempool", preferenceKey: "kernel_log_category_mempool", kernelCategory: 5),
        KernelLogCategorySetting(id: "prune", title: "Prune", preferenceKey: "kernel_log_category_prune", kernelCategory: 6),
        KernelLogCategorySetting(id: "rand", title: "Rand", preferenceKey: "kernel_log_category_rand", kernelCategory: 7),
        KernelLogCategorySetting(id: "reindex", title: "Reindex", preferenceKey: "kernel_log_category_reindex", kernelCategory: 8),
        KernelLogCategorySetting(id: "validation", title: "Validation", preferenceKey: "kernel_log_category_validation", kernelCategory: 9),
        KernelLogCategorySetting(id: "kernel", title: "Kernel", preferenceKey: "kernel_log_category_kernel", kernelCategory: 10),
    ]

    static func registerDefaults(_ defaults: UserDefaults = .standard) {
        defaults.register(defaults: defaultValues)
    }

    static func snapshot(_ defaults: UserDefaults = .standard) -> KernelLogSettingsSnapshot {
        let isEnabled = defaults.object(forKey: loggingEnabledKey) as? Bool ?? true
        let internalLogsEnabled = defaults.object(forKey: internalLogsEnabledKey) as? Bool ?? true
        guard isEnabled else {
            return KernelLogSettingsSnapshot(
                isEnabled: false, internalLogsEnabled: false, enabledCategories: [],
                logTimestamps: false, logTimeMicros: false, logThreadNames: false,
                logSourceLocations: false, alwaysPrintCategoryLevels: false
            )
        }

        let enabledCategories = categories.compactMap { category in
            let isCategoryEnabled = defaults.object(forKey: category.preferenceKey) as? Bool ?? false
            return isCategoryEnabled ? category.kernelCategory : nil
        }

        return KernelLogSettingsSnapshot(
            isEnabled: true,
            internalLogsEnabled: internalLogsEnabled,
            enabledCategories: enabledCategories,
            logTimestamps: defaults.bool(forKey: logTimestampsKey),
            logTimeMicros: defaults.bool(forKey: logTimeMicrosKey),
            logThreadNames: defaults.bool(forKey: logThreadNamesKey),
            logSourceLocations: defaults.bool(forKey: logSourceLocationsKey),
            alwaysPrintCategoryLevels: defaults.bool(forKey: alwaysPrintCategoryLevelsKey)
        )
    }

    static func isCategoryEnabled(_ category: UInt8, defaults: UserDefaults = .standard) -> Bool {
        let snapshot = snapshot(defaults)
        guard snapshot.isEnabled else {
            return false
        }

        return snapshot.enabledCategories.contains(category)
    }

    static func categoryForRawLogLine(_ line: String) -> UInt8? {
        var searchStart = line.startIndex

        while let openingBracketIndex = line[searchStart...].firstIndex(of: "[") {
            guard let closingBracketIndex = line[openingBracketIndex...].firstIndex(of: "]"),
                  closingBracketIndex > openingBracketIndex else {
                return nil
            }

            let nameStartIndex = line.index(after: openingBracketIndex)
            let categoryName = String(line[nameStartIndex..<closingBracketIndex]).lowercased()
            if let category = categories.first(where: { $0.id == categoryName }) {
                return category.kernelCategory
            }

            searchStart = line.index(after: openingBracketIndex)
        }

        return nil
    }

    static func notifyChanged() {
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    private static var defaultValues: [String: Any] {
        var values: [String: Any] = [
            loggingEnabledKey: true,
            internalLogsEnabledKey: true,
        ]

        for category in categories {
            values[category.preferenceKey] = false
        }

        values[logTimestampsKey] = false
        values[logTimeMicrosKey] = false
        values[logThreadNamesKey] = false
        values[logSourceLocationsKey] = false
        values[alwaysPrintCategoryLevelsKey] = false

        return values
    }
}
