import CoreGraphics
import EventKit
import Foundation
import Observation

// 初回セットアップ画面の ViewModel
@MainActor
@Observable
final class InitialSetupViewModel {
    var currentStep: InitialSetupStep = .welcome
    var state: InitialSetupState = .editing
    var googleAiApiKey: String
    var rssURL = ""
    var userPrompt = ""
    var schedule: UpdateSchedule = .onceADay
    var automaticGenerationEnabled = true
    var skipIfNoChanges = false
    var wifiOnlyGeneration = false
    var forceFlexTier = false
    var notificationsEnabled = true
    var availableCalendars: [CalendarSourceItem] = []
    var selectedCalendarIds = Set<String>()
    var calendarAuthStatus: EKAuthorizationStatus
    var errorMessage: String?
    var infoMessage: String?

    private let environment: AppEnvironment
    private var resolvedRssURL: String?
    private var preparedGenerationPermissions = false

    init(environment: AppEnvironment) {
        self.environment = environment
        let config = environment.configService.config
        googleAiApiKey = environment.configService.googleAiApiKey
        userPrompt = config.userPrompt
        automaticGenerationEnabled = true
        schedule = .onceADay
        skipIfNoChanges = config.skipIfNoChanges
        wifiOnlyGeneration = config.wifiOnlyGeneration
        forceFlexTier = config.forceFlexTier
        notificationsEnabled = config.notificationsEnabled
        selectedCalendarIds = Set(config.targetCalendarIds)
        calendarAuthStatus = environment.calendarService.authorizationStatus()
    }

    var isBusy: Bool { state.isBusy || environment.isGenerating }
    var isFirstStep: Bool { currentStep == .welcome || currentStep == .wallpaperInstructions }
    var isGenerationStep: Bool { currentStep == .generation }
    var isCompletionStep: Bool { currentStep == .wallpaperInstructions }

    var primaryButtonTitle: String {
        if isCompletionStep { return "ホームへ" }
        if isGenerationStep { return "初回生成を開始" }
        return currentStep == .automaticGeneration ? "権限を確認して生成へ進む" : "次へ"
    }

    var canUseCalendar: Bool {
        calendarAuthStatus == .fullAccess
    }

    var isCalendarDenied: Bool {
        calendarAuthStatus == .denied || calendarAuthStatus == .restricted
    }

    var trimmedApiKey: String {
        googleAiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canRunInitialGeneration: Bool {
        !trimmedApiKey.isEmpty && !isBusy
    }

    var wallpaperInstructions: String {
        environment.wallpaperService.wallpaperInstructions()
    }

    func loadInitialData() {
        calendarAuthStatus = environment.calendarService.authorizationStatus()
        guard canUseCalendar else { return }
        loadCalendarsAndSelectDefaultIfNeeded()
    }

    func goBack() {
        guard !isBusy,
              currentStep != .wallpaperInstructions,
              let previous = InitialSetupStep(rawValue: currentStep.rawValue - 1) else {
            return
        }
        errorMessage = nil
        infoMessage = nil
        if previous == .automaticGeneration {
            preparedGenerationPermissions = false
        }
        currentStep = previous
    }

    func advance() async {
        guard !isBusy else { return }
        errorMessage = nil
        infoMessage = nil

        switch currentStep {
        case .apiKey:
            guard !trimmedApiKey.isEmpty else {
                errorMessage = "Google AI API キーを入力してください。"
                return
            }
        case .context:
            guard await resolveRssIfNeeded() else { return }
        case .automaticGeneration:
            guard await prepareGenerationPermissions() else { return }
        default:
            break
        }

        guard let next = InitialSetupStep(rawValue: currentStep.rawValue + 1) else { return }
        currentStep = next
    }

    func requestCalendarAccess() async {
        guard !isBusy else { return }
        errorMessage = nil
        infoMessage = nil
        state = .requestingCalendar
        defer { state = .editing }

        do {
            _ = try await environment.calendarService.requestAccess()
            calendarAuthStatus = environment.calendarService.authorizationStatus()
            if canUseCalendar {
                loadCalendarsAndSelectDefaultIfNeeded()
                infoMessage = "カレンダーに接続しました。"
            } else {
                infoMessage = "カレンダーはスキップできます。"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleCalendar(_ calendarId: String) {
        if selectedCalendarIds.contains(calendarId) {
            selectedCalendarIds.remove(calendarId)
        } else {
            selectedCalendarIds.insert(calendarId)
        }
    }

    func togglePromptTemplate(_ template: String) {
        userPrompt = userPrompt == template ? "" : template
    }

    func runInitialGeneration(
        screenSize: CGSize,
        displayScale: CGFloat
    ) async {
        guard !isBusy else { return }
        errorMessage = nil
        infoMessage = nil

        guard !trimmedApiKey.isEmpty else {
            errorMessage = "Google AI API キーを入力してください。"
            currentStep = .apiKey
            return
        }

        if !rssURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           resolvedRssURL == nil {
            errorMessage = "RSS フィードを確認できていません。コンテキスト設定を確認してください。"
            currentStep = .context
            return
        }

        guard preparedGenerationPermissions,
              environment.wallpaperService.hasPhotoLibraryAccess() else {
            errorMessage = "写真ライブラリへのアクセス権限が必要です。設定アプリから許可してから再試行してください。"
            currentStep = .automaticGeneration
            return
        }

        state = .saving
        saveInitialSettings(
            screenSize: screenSize,
            displayScale: displayScale
        )

        state = .generating
        let result = await environment.coordinator.runManual()
        if result.isSuccess, result.photoAssetId != nil {
            environment.configService.update {
                $0.hasCompletedInitialSetup = true
            }
            environment.backgroundTaskService.scheduleNextBackgroundTask()
            state = .completed
            currentStep = .wallpaperInstructions
            infoMessage = "WondayWall アルバムに最初の壁紙を保存しました。"
            return
        }

        state = .editing
        errorMessage = result.errorSummary ?? "初回生成に失敗しました。設定を確認して再試行してください。"
    }

    func completeSetup(onCompleted: @escaping @MainActor () -> Void) {
        guard currentStep == .wallpaperInstructions else { return }
        environment.configService.update {
            $0.hasCompletedInitialSetup = true
        }
        onCompleted()
    }

    private func loadCalendarsAndSelectDefaultIfNeeded() {
        availableCalendars = environment.contextService.fetchAvailableCalendars()
        guard selectedCalendarIds.isEmpty else { return }

        if let defaultId = environment.calendarService.defaultCalendarIdentifierForNewEvents(),
           availableCalendars.contains(where: { $0.id == defaultId }) {
            selectedCalendarIds.insert(defaultId)
        } else if let first = availableCalendars.first {
            selectedCalendarIds.insert(first.id)
        }
    }

    private func resolveRssIfNeeded() async -> Bool {
        let sourceURL = rssURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceURL.isEmpty else {
            resolvedRssURL = nil
            return true
        }

        guard RssSourceResolver.isSupportedAbsoluteURL(sourceURL) else {
            errorMessage = "有効な RSS フィード URL を入力してください。"
            return false
        }

        state = .resolvingRss
        defer { state = .editing }

        guard let resolvedURL = await RssSourceResolver.resolve(from: sourceURL) else {
            errorMessage = "指定の URL から RSS フィードを見つけられませんでした。"
            return false
        }

        resolvedRssURL = resolvedURL
        return true
    }

    private func prepareGenerationPermissions() async -> Bool {
        state = .requestingPhotos
        guard await environment.wallpaperService.canSaveToPhotos() else {
            preparedGenerationPermissions = false
            state = .editing
            errorMessage = "写真ライブラリへのアクセス権限が必要です。設定アプリから許可してから再試行してください。"
            return false
        }

        state = .requestingNotifications
        if notificationsEnabled {
            let notificationGranted = await environment.notificationService.requestPermission()
            notificationsEnabled = notificationGranted
            if !notificationGranted {
                infoMessage = "通知権限が許可されなかったため、生成完了通知はオフにしました。"
            }
        }

        preparedGenerationPermissions = true
        state = .editing
        return true
    }

    private func saveInitialSettings(
        screenSize: CGSize,
        displayScale: CGFloat
    ) {
        environment.configService.googleAiApiKey = trimmedApiKey

        let pixelWidth = Double(screenSize.width * displayScale)
        let pixelHeight = Double(screenSize.height * displayScale)
        let normalizedWidth = min(pixelWidth, pixelHeight)
        let normalizedHeight = max(pixelWidth, pixelHeight)
        let selectedIds = Array(selectedCalendarIds)

        environment.configService.update { config in
            config.targetCalendarIds = selectedIds
            if let resolvedRssURL, !config.rssSources.contains(resolvedRssURL) {
                config.rssSources.append(resolvedRssURL)
            }
            config.userPrompt = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            config.autoGenerationEnabled = automaticGenerationEnabled
            config.schedule = schedule
            config.skipIfNoChanges = skipIfNoChanges
            config.wifiOnlyGeneration = wifiOnlyGeneration
            config.forceFlexTier = forceFlexTier
            config.notificationsEnabled = notificationsEnabled
            config.hasCompletedInitialSetup = false
            config.screenNativePixelWidth = normalizedWidth
            config.screenNativePixelHeight = normalizedHeight
        }
    }
}
