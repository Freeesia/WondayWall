import AppIntents
import Photos
import SwiftUI
import UIKit
import WidgetKit

enum WidgetInfoPage: String {
    case calendar
    case news
}

enum WidgetInfoPageIntentValue: String, AppEnum {
    case calendar
    case news

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "表示ページ")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .calendar: DisplayRepresentation(title: "予定"),
        .news: DisplayRepresentation(title: "ニュース")
    ]

    var page: WidgetInfoPage {
        switch self {
        case .calendar: return .calendar
        case .news: return .news
        }
    }
}

enum WidgetInfoPageStore {
    private static let key = "wondaywall.widget.infoPage"

    static func current() -> WidgetInfoPage? {
        guard let value = UserDefaults(suiteName: WidgetSharedConstants.appGroupIdentifier)?
            .string(forKey: key)
        else { return nil }
        return WidgetInfoPage(rawValue: value)
    }

    static func set(_ page: WidgetInfoPage) {
        UserDefaults(suiteName: WidgetSharedConstants.appGroupIdentifier)?
            .set(page.rawValue, forKey: key)
    }
}

struct SelectWidgetInfoPageIntent: AppIntent {
    static var title: LocalizedStringResource = "ウィジェット表示を切り替え"
    static var description = IntentDescription("ウィジェットに表示する予定またはニュースを切り替えます。")
    static var openAppWhenRun = false

    @Parameter(title: "ページ")
    var page: WidgetInfoPageIntentValue

    init() {
        page = .calendar
    }

    init(page: WidgetInfoPageIntentValue) {
        self.page = page
    }

    func perform() async throws -> some IntentResult {
        WidgetInfoPageStore.set(page.page)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSharedConstants.kind)
        return .result()
    }
}

struct WondayWallWidgetEntry: TimelineEntry {
    let date: Date
    let state: WidgetSharedState
    let image: UIImage?
    let faviconImages: [String: UIImage]
}

struct WondayWallWidgetProvider: TimelineProvider {
    private static let imageTargetSize = CGSize(width: 720, height: 720)

    func placeholder(in context: Context) -> WondayWallWidgetEntry {
        WondayWallWidgetEntry(date: Date(), state: .placeholder, image: nil, faviconImages: [:])
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (WondayWallWidgetEntry) -> Void
    ) {
        Task {
            let state = makeDisplayState()
            let faviconImages = await loadFaviconImages(for: state)
            completion(WondayWallWidgetEntry(
                date: Date(),
                state: state,
                image: loadImage(for: state),
                faviconImages: faviconImages
            ))
        }
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<WondayWallWidgetEntry>) -> Void
    ) {
        Task {
            let state = makeDisplayState()
            let faviconImages = await loadFaviconImages(for: state)
            let entry = WondayWallWidgetEntry(
                date: Date(),
                state: state,
                image: loadImage(for: state),
                faviconImages: faviconImages
            )
            let refreshDate = nextRefreshDate(for: state)
            completion(Timeline(entries: [entry], policy: .after(refreshDate)))
        }
    }

    private func nextRefreshDate(for state: WidgetSharedState) -> Date {
        let now = Date()
        let hourlyRefreshDate = now.addingTimeInterval(60 * 60)
        let candidates = [state.nextSlotStartsAt, hourlyRefreshDate]
            .compactMap { $0 }
            .filter { $0 > now }
        return candidates.min() ?? hourlyRefreshDate
    }

    private func makeDisplayState() -> WidgetSharedState {
        let configService = AppConfigService()
        let historyService = HistoryService(repairInterruptedGeneration: false)
        let config = configService.config
        let now = Date()
        let currentSlotStartedAt = ScheduleHelper.getLatestScheduledSlotAtOrBefore(
            now,
            schedule: config.schedule
        )
        let nextSlotStartsAt = ScheduleHelper.getNextScheduledSlotAfter(
            now,
            schedule: config.schedule
        )
        let isCurrentSlotProcessed = historyService.isSlotProcessed(
            startedAt: currentSlotStartedAt
        )
        let isGenerating = historyService.loadNewestFirst().first?.isGenerating == true
        let isConfigured = config.hasCompletedInitialSetup

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

        var state = WidgetSharedState(
            status: status,
            isGenerating: isGenerating,
            generationProgress: nil,
            isCurrentSlotProcessed: isCurrentSlotProcessed,
            currentSlotStartedAt: currentSlotStartedAt,
            nextSlotStartsAt: nextSlotStartsAt,
            latestDisplayHistory: nil,
            canOpenGenerationConfirmation: isConfigured && !isGenerating && !isCurrentSlotProcessed,
            usedCalendarEvents: [],
            usedNewsTopics: [],
            updatedAt: now
        )

        if let item = historyService.getLatestDisplayCandidate(since: currentSlotStartedAt) {
            state.latestDisplayHistory = WidgetDisplayHistory(
                id: item.id,
                executedAt: item.executedAt,
                status: item.status.rawValue,
                photoAssetId: item.photoAssetId
            )
        } else {
            state.latestDisplayHistory = nil
        }

        state.usedNewsTopics = historyService.getDisplayNewsTopics(
            since: currentSlotStartedAt
        )
        .prefix(8)
        .map {
            WidgetNewsTopic(
                id: $0.id,
                title: $0.title,
                url: $0.url,
                publishedAt: $0.publishedAt
            )
        }

        state.usedCalendarEvents = historyService.getDisplayCalendarEvents(
            since: currentSlotStartedAt
        )
        .prefix(4)
        .map {
            WidgetCalendarEvent(
                id: $0.id,
                title: $0.title,
                startTime: $0.startTime,
                endTime: $0.endTime,
                isAllDay: $0.isAllDay,
                location: $0.location
            )
        }
        return state
    }

    private func loadImage(for state: WidgetSharedState) -> UIImage? {
        guard let assetId = state.latestDisplayHistory?.photoAssetId else { return nil }
        let authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            return nil
        }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let asset = assets.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        options.isSynchronous = true

        var result: UIImage?
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: Self.imageTargetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            result = image
        }
        return result
    }

    private func loadFaviconImages(for state: WidgetSharedState) async -> [String: UIImage] {
        await withTaskGroup(of: (String, UIImage?).self) { group in
            for item in state.usedNewsTopics {
                guard let faviconURL = WidgetNewsURLHelper.faviconURL(for: item.url) else { continue }
                group.addTask {
                    let image = await Self.loadImage(from: faviconURL)
                    return (item.id, image)
                }
            }

            var images: [String: UIImage] = [:]
            for await (id, image) in group {
                if let image {
                    images[id] = image
                }
            }
            return images
        }
    }

    private static func loadImage(from url: URL) async -> UIImage? {
        let cacheURL = faviconCacheFileURL(for: url)
        if let data = try? Data(contentsOf: cacheURL),
           let image = UIImage(data: data) {
            return image
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 4

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else { return nil }

        try? data.write(to: cacheURL, options: .atomic)
        return UIImage(data: data)
    }

    private static func faviconCacheFileURL(for url: URL) -> URL {
        removeLegacyFaviconCacheIfNeeded()
        let directory = FileHelper.sharedCacheDirectory.appendingPathComponent(
            "favicons",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = url.absoluteString
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics)?
            .appending(".png") ?? "favicon.png"
        return directory.appendingPathComponent(fileName)
    }

    private static func removeLegacyFaviconCacheIfNeeded() {
        let legacyDirectory = FileHelper.sharedDataDirectory.appendingPathComponent(
            "favicons",
            isDirectory: true
        )
        try? FileManager.default.removeItem(at: legacyDirectory)
    }
}

struct WondayWallWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WondayWallWidgetEntry

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                wallpaperBackground(size: proxy.size)
                overlayContent
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .widgetURL(rootWidgetURL)
        .containerBackground(for: .widget) {
            Color(.secondarySystemBackground)
        }
    }

    @ViewBuilder
    private func wallpaperBackground(size: CGSize) -> some View {
        if let image = entry.image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            LinearGradient(
                colors: [Color(.systemGray5), Color(.systemGray3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    @ViewBuilder
    private var overlayContent: some View {
        if entry.state.canOpenGenerationConfirmation {
            centeredGenerateContent
        } else {
            switch family {
            case .systemSmall:
                smallContent
            case .systemLarge:
                largeContent
            default:
                mediumContent
            }
        }
    }

    private var centeredGenerateContent: some View {
        VStack {
            generateLink(compact: family == .systemSmall)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var smallContent: some View {
        if shouldShowSmallNewsButton {
            smallNewsButton
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Spacer()
                if shouldShowStatus {
                    statusLabel
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .background {
                if shouldShowStatus {
                    bottomScrim
                }
            }
        }
    }

    private var mediumContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if shouldShowStatus {
                statusLabel
            }

            if shouldShowInfo {
                infoContent(compact: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            overlayScrim
        }
    }

    private var largeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if shouldShowStatus {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        statusLabel
                    }
                    Spacer()
                }
            }

            if shouldShowInfo {
                infoContent(compact: false)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            overlayScrim
        }
    }

    private var statusLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: statusIcon)
                .font(.caption.weight(.semibold))
            Text(statusText)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .shadow(radius: 2)
    }

    private var smallNewsButton: some View {
        Link(destination: widgetNewsURL) {
            HStack(spacing: 6) {
                Image(systemName: "newspaper.fill")
                Text("本日のニュース")
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.54))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 3)
        }
    }

    private func generateLink(compact: Bool) -> some View {
        Link(destination: generationURL) {
            HStack(spacing: compact ? 8 : 10) {
                Image(systemName: "sparkles")
                Text(compact ? "生成" : "壁紙生成")
            }
            .font((compact ? Font.headline : Font.title3).weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 18 : 22)
            .padding(.vertical, compact ? 12 : 14)
            .background(Color.accentColor)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.36), radius: 10, x: 0, y: 4)
        }
    }

    @ViewBuilder
    private func infoContent(compact: Bool) -> some View {
        let page = selectedInfoPage
        let limit = infoLimit(for: page, compact: compact)

        VStack(alignment: .leading, spacing: compact ? 7 : 10) {
            if shouldShowInfoPager {
                infoPager(selected: page, compact: compact)
            }

            switch page {
            case .calendar:
                calendarList(limit: limit, compact: compact)
            case .news:
                newsList(limit: limit, compact: compact)
            }
        }
    }

    private func infoPager(selected: WidgetInfoPage, compact: Bool) -> some View {
        HStack(spacing: 6) {
            infoPageButton(
                title: "予定",
                page: .calendar,
                selected: selected == .calendar,
                compact: compact
            )
            infoPageButton(
                title: "ニュース",
                page: .news,
                selected: selected == .news,
                compact: compact
            )
        }
    }

    private func infoPageButton(
        title: String,
        page: WidgetInfoPageIntentValue,
        selected: Bool,
        compact: Bool
    ) -> some View {
        Button(intent: SelectWidgetInfoPageIntent(page: page)) {
            Text(title)
                .font((compact ? Font.caption : Font.callout).weight(.bold))
                .foregroundStyle(selected ? Color.black : Color.white)
                .lineLimit(1)
                .padding(.horizontal, compact ? 10 : 12)
                .padding(.vertical, compact ? 5 : 7)
                .frame(maxWidth: .infinity)
                .background(selected ? Color.white.opacity(0.92) : Color.black.opacity(0.34))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func calendarList(limit: Int, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            ForEach(Array(calendarEvents.prefix(limit))) { item in
                calendarRow(item, compact: compact)
            }
        }
    }

    private func calendarRow(_ item: WidgetCalendarEvent, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font((compact ? Font.callout : Font.title3).weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            HStack(spacing: 5) {
                Image(systemName: item.isAllDay ? "calendar" : "clock")
                Text(calendarTimeText(for: item))
                    .lineLimit(1)
                if let location = item.location, !location.isEmpty {
                    Text("・\(location)")
                        .lineLimit(1)
                }
            }
            .font((compact ? Font.caption : Font.callout).weight(.semibold))
            .foregroundStyle(.white.opacity(0.86))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, compact ? 10 : 12)
        .padding(.vertical, compact ? 8 : 10)
        .background(Color.black.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func newsList(limit: Int, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            ForEach(Array(newsItems.prefix(limit))) { item in
                if let url = WidgetNewsURLHelper.newsURL(item.url) {
                    Link(destination: url) {
                        newsRow(item, compact: compact)
                    }
                } else {
                    newsRow(item, compact: compact)
                }
            }
        }
    }

    private func newsRow(_ item: WidgetNewsTopic, compact: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            faviconImage(for: item)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(compact ? 1 : 2)
                    .multilineTextAlignment(.leading)

                Text(item.publishedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 6 : 8)
        .background(Color.black.opacity(0.38))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func faviconImage(for item: WidgetNewsTopic) -> some View {
        if let image = entry.faviconImages[item.id] {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
        } else {
            fallbackFavicon
        }
    }

    private var fallbackFavicon: some View {
        Image(systemName: "globe")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(.white.opacity(0.76))
            .frame(width: 16, height: 16)
    }

    private var statusText: String {
        switch entry.state.status {
        case .unconfigured:
            return "初期設定が必要です"
        case .pending:
            return ""
        case .processed:
            return "WondayWall"
        case .generating:
            if let progress = entry.state.generationProgress {
                return "生成中 \(progress)%"
            }
            return "生成中"
        }
    }

    private var shouldShowStatus: Bool {
        entry.state.status != .processed && entry.state.status != .pending
    }

    private var shouldShowInfo: Bool {
        entry.state.status == .processed && (!calendarEvents.isEmpty || !newsItems.isEmpty)
    }

    private var shouldShowInfoPager: Bool {
        !calendarEvents.isEmpty && !newsItems.isEmpty
    }

    private var shouldShowSmallNewsButton: Bool {
        family == .systemSmall && entry.state.status == .processed
    }

    private func infoLimit(for page: WidgetInfoPage, compact: Bool) -> Int {
        switch (page, compact, shouldShowInfoPager) {
        case (.news, true, true):
            return 2
        case (.news, true, false):
            return 3
        case (.news, false, _):
            return 5
        case (.calendar, true, _):
            return 2
        case (.calendar, false, _):
            return 4
        }
    }

    private var calendarEvents: [WidgetCalendarEvent] {
        entry.state.usedCalendarEvents ?? []
    }

    private var newsItems: [WidgetNewsTopic] {
        entry.state.usedNewsTopics
    }

    private var selectedInfoPage: WidgetInfoPage {
        let storedPage = WidgetInfoPageStore.current()
        if storedPage == .calendar, !calendarEvents.isEmpty {
            return .calendar
        }
        if storedPage == .news, !newsItems.isEmpty {
            return .news
        }
        if !newsItems.isEmpty {
            return .news
        }
        return .calendar
    }

    private var statusIcon: String {
        switch entry.state.status {
        case .unconfigured: return "gearshape"
        case .pending: return "sparkles"
        case .processed: return "checkmark.circle.fill"
        case .generating: return "hourglass"
        }
    }

    private var generationURL: URL {
        var components = URLComponents()
        components.scheme = "wondaywall"
        components.host = "widget"
        components.path = "/generate-confirmation"
        components.queryItems = [
            URLQueryItem(
                name: "slotStartedAt",
                value: ISO8601DateFormatter().string(from: entry.state.currentSlotStartedAt)
            )
        ]
        return components.url ?? URL(string: "wondaywall://widget/generate-confirmation")!
    }

    private var widgetNewsURL: URL {
        URL(string: "wondaywall://widget/news")!
    }

    private var rootWidgetURL: URL? {
        guard family == .systemSmall else { return nil }
        if entry.state.canOpenGenerationConfirmation {
            return generationURL
        }
        if shouldShowSmallNewsButton {
            return widgetNewsURL
        }
        return nil
    }

    private func calendarTimeText(for item: WidgetCalendarEvent) -> String {
        if item.isAllDay {
            return "終日"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.setLocalizedDateFormatFromTemplate("M/d HH:mm")
        let startText = formatter.string(from: item.startTime)
        guard let endTime = item.endTime else {
            return startText
        }

        let calendar = Calendar.current
        if calendar.isDate(item.startTime, inSameDayAs: endTime) {
            let timeFormatter = DateFormatter()
            timeFormatter.locale = Locale(identifier: "ja_JP")
            timeFormatter.setLocalizedDateFormatFromTemplate("HH:mm")
            return "\(startText) - \(timeFormatter.string(from: endTime))"
        }
        return "\(startText) - \(formatter.string(from: endTime))"
    }

    @ViewBuilder
    private var overlayScrim: some View {
        if shouldShowStatus || shouldShowInfo {
            bottomScrim
        }
    }

    private var bottomScrim: LinearGradient {
        LinearGradient(
            colors: [.clear, Color.black.opacity(shouldShowInfo ? 0.5 : 0.68)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

enum WidgetNewsURLHelper {
    static func newsURL(_ urlString: String?) -> URL? {
        guard let urlString,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }

    static func faviconURL(for urlString: String?) -> URL? {
        guard let url = newsURL(urlString),
              let host = url.host
        else { return nil }

        var components = URLComponents(string: "https://www.google.com/s2/favicons")
        components?.queryItems = [
            URLQueryItem(name: "domain", value: host.lowercased()),
            URLQueryItem(name: "sz", value: "64")
        ]
        return components?.url
    }
}

@main
struct WondayWallWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WidgetSharedConstants.kind,
            provider: WondayWallWidgetProvider()
        ) { entry in
            WondayWallWidgetView(entry: entry)
        }
        .configurationDisplayName("WondayWall")
        .description("現在の生成スロットと壁紙履歴を表示します。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemMedium) {
    WondayWallWidget()
} timeline: {
    WondayWallWidgetEntry(date: Date(), state: .placeholder, image: nil, faviconImages: [:])
}
