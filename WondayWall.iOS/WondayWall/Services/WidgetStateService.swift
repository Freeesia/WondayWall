import Foundation
import WidgetKit

// ウィジェット表示用の共有状態を作成・保存するサービス
enum WidgetStateService {
    @MainActor
    static func refresh(environment: AppEnvironment) async {
        guard let stateURL = WidgetSharedConstants.stateFileURL(),
              let containerURL = WidgetSharedConstants.sharedContainerURL()
        else { return }

        let state = makeState(environment: environment)
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
    private static func makeState(environment: AppEnvironment) -> WidgetSharedState {
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
        let isCurrentSlotProcessed = environment.historyService.isSlotProcessed(
            startedAt: currentSlotStartedAt
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
            latestDisplayHistory: nil,
            canOpenGenerationConfirmation: isConfigured && !isGenerating && !isCurrentSlotProcessed,
            usedNewsTopics: [],
            updatedAt: now
        )
    }
}
