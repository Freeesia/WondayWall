import Foundation
import UIKit
import WidgetKit

// ウィジェット表示用の共有状態を作成・保存するサービス
enum WidgetStateService {
    private static let thumbnailSize = CGSize(width: 640, height: 640)

    @MainActor
    static func refresh(environment: AppEnvironment) async {
        guard let stateURL = WidgetSharedConstants.stateFileURL(),
              let containerURL = WidgetSharedConstants.sharedContainerURL()
        else { return }

        let state = await makeState(environment: environment, containerURL: containerURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else { return }

        try? FileManager.default.createDirectory(
            at: containerURL,
            withIntermediateDirectories: true
        )
        try? data.write(to: stateURL, options: .atomic)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSharedConstants.kind)
    }

    @MainActor
    private static func makeState(
        environment: AppEnvironment,
        containerURL: URL
    ) async -> WidgetSharedState {
        let config = environment.configService.config
        let now = Date()
        let currentSlotStartedAt = ScheduleHelper.getLatestScheduledSlotAtOrBefore(
            now,
            schedule: config.schedule
        )
        let nextSlotStartsAt = ScheduleHelper.getNextScheduledSlotAfter(
            now,
            schedule: config.schedule
        )
        let history = environment.historyService.load()
        let lastCompleted = history
            .filter { !$0.isGenerating }
            .sorted { $0.executedAt > $1.executedAt }
            .first
        let isCurrentSlotProcessed = lastCompleted.map {
            $0.executedAt >= currentSlotStartedAt
        } ?? false

        let slotHistory = history.first {
            !$0.isGenerating && $0.executedAt >= currentSlotStartedAt
        }
        let latestSuccess = history.first { $0.isSuccess && !$0.isSkipped }
        let imageHistory: HistoryItem?
        if let slotHistory, slotHistory.photoAssetId != nil {
            imageHistory = slotHistory
        } else {
            imageHistory = latestSuccess
        }
        let newsSource = nonEmpty(slotHistory?.usedNewsTopics)
            ?? nonEmpty(latestSuccess?.usedNewsTopics)
            ?? []
        let displayHistory = await makeDisplayHistory(
            from: imageHistory,
            wallpaperService: environment.wallpaperService,
            containerURL: containerURL
        )

        let isConfigured = config.hasCompletedInitialSetup
            && !environment.configService.googleAiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isGenerating = environment.isGenerating
        let status: WidgetSlotStatus
        if !isConfigured {
            status = .unconfigured
        } else if isGenerating {
            status = .generating
        } else if isCurrentSlotProcessed {
            status = .processed
        } else {
            status = .pending
        }

        return WidgetSharedState(
            status: status,
            isGenerating: isGenerating,
            generationProgress: environment.generationProgress,
            isCurrentSlotProcessed: isCurrentSlotProcessed,
            currentSlotStartedAt: currentSlotStartedAt,
            nextSlotStartsAt: nextSlotStartsAt,
            latestDisplayHistory: displayHistory,
            canOpenGenerationConfirmation: isConfigured && !isGenerating && !isCurrentSlotProcessed,
            usedNewsTopics: newsSource.prefix(3).map {
                WidgetNewsTopic(
                    id: $0.id,
                    title: $0.title,
                    url: $0.url,
                    publishedAt: $0.publishedAt
                )
            },
            updatedAt: now
        )
    }

    private static func makeDisplayHistory(
        from item: HistoryItem?,
        wallpaperService: WallpaperService,
        containerURL: URL
    ) async -> WidgetDisplayHistory? {
        guard let item else { return nil }
        let thumbnailFileName = await makeThumbnail(
            for: item,
            wallpaperService: wallpaperService,
            containerURL: containerURL
        )
        return WidgetDisplayHistory(
            id: item.id,
            executedAt: item.executedAt,
            status: item.status.rawValue,
            thumbnailFileName: thumbnailFileName
        )
    }

    private static func makeThumbnail(
        for item: HistoryItem,
        wallpaperService: WallpaperService,
        containerURL: URL
    ) async -> String? {
        guard let assetId = item.photoAssetId else { return nil }
        guard let image = await wallpaperService.loadImage(
            assetId: assetId,
            targetSize: thumbnailSize
        ) else { return nil }
        let fileName = "widget-thumbnail-\(item.id.uuidString).jpg"
        let fileURL = containerURL.appendingPathComponent(fileName)
        guard let data = image.jpegData(compressionQuality: 0.82) else { return nil }
        try? data.write(to: fileURL, options: .atomic)
        return fileName
    }

    private static func nonEmpty<T>(_ values: [T]?) -> [T]? {
        guard let values, !values.isEmpty else { return nil }
        return values
    }
}
