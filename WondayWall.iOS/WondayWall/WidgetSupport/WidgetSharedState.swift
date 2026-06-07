import Foundation

// アプリ本体と Widget Extension の間で共有するウィジェット表示状態
struct WidgetSharedState: Codable {
    var status: WidgetSlotStatus
    var isGenerating: Bool
    var generationProgress: Int?
    var isCurrentSlotProcessed: Bool
    var currentSlotStartedAt: Date
    var nextSlotStartsAt: Date?
    var latestDisplayHistory: WidgetDisplayHistory?
    var canOpenGenerationConfirmation: Bool
    var usedNewsTopics: [WidgetNewsTopic]
    var updatedAt: Date

    static var placeholder: WidgetSharedState {
        WidgetSharedState(
            status: .unconfigured,
            isGenerating: false,
            generationProgress: nil,
            isCurrentSlotProcessed: false,
            currentSlotStartedAt: Date(),
            nextSlotStartsAt: nil,
            latestDisplayHistory: nil,
            canOpenGenerationConfirmation: false,
            usedNewsTopics: [],
            updatedAt: Date()
        )
    }
}

enum WidgetSlotStatus: String, Codable {
    case unconfigured
    case pending
    case processed
    case generating
}

struct WidgetDisplayHistory: Codable, Identifiable {
    var id: UUID
    var executedAt: Date
    var status: String
    var photoAssetId: String?
}

struct WidgetNewsTopic: Codable, Identifiable {
    var id: String
    var title: String
    var url: String?
    var publishedAt: Date
}

enum WidgetSharedConstants {
    static let kind = "WondayWallWidget"
    static let stateFileName = "widget-state.json"

    static var appGroupIdentifier: String? {
        Bundle.main.object(forInfoDictionaryKey: "WondayWallAppGroupIdentifier") as? String
    }

    static func sharedContainerURL() -> URL? {
        guard let appGroupIdentifier else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    static func stateFileURL() -> URL? {
        sharedContainerURL()?.appendingPathComponent(stateFileName)
    }
}
