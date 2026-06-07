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
}

struct WondayWallWidgetProvider: TimelineProvider {
    private static let imageTargetSize = CGSize(width: 720, height: 720)

    func placeholder(in context: Context) -> WondayWallWidgetEntry {
        WondayWallWidgetEntry(date: Date(), state: .placeholder, image: nil)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (WondayWallWidgetEntry) -> Void
    ) {
        let state = loadState() ?? .placeholder
        completion(WondayWallWidgetEntry(date: Date(), state: state, image: loadImage(for: state)))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<WondayWallWidgetEntry>) -> Void
    ) {
        let state = loadState() ?? .placeholder
        let entry = WondayWallWidgetEntry(date: Date(), state: state, image: loadImage(for: state))
        let refreshDate = state.nextSlotStartsAt ?? Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }

    private func loadState() -> WidgetSharedState? {
        guard let url = WidgetSharedConstants.stateFileURL(),
              let data = try? Data(contentsOf: url)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(WidgetSharedState.self, from: data) else {
            return nil
        }
        return makeDisplayState(from: state)
    }

    private func makeDisplayState(from sharedState: WidgetSharedState) -> WidgetSharedState {
        let historyService = HistoryService(repairInterruptedGeneration: false)
        var state = sharedState
        let isCurrentSlotProcessed = historyService.isSlotProcessed(
            startedAt: state.currentSlotStartedAt
        )

        state.isCurrentSlotProcessed = isCurrentSlotProcessed
        if state.status != .unconfigured && state.status != .generating {
            state.status = isCurrentSlotProcessed ? .processed : .pending
            state.canOpenGenerationConfirmation = state.canOpenGenerationConfirmation
                && !isCurrentSlotProcessed
        }

        if let item = historyService.getLatestDisplayCandidate(since: state.currentSlotStartedAt) {
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
            since: state.currentSlotStartedAt
        )
        .prefix(3)
        .map {
            WidgetNewsTopic(
                id: $0.id,
                title: $0.title,
                url: $0.url,
                publishedAt: $0.publishedAt
            )
        }

        state.usedCalendarEvents = historyService.getDisplayCalendarEvents(
            since: state.currentSlotStartedAt
        )
        .prefix(3)
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
        .widgetURL(entry.state.canOpenGenerationConfirmation ? generationURL : nil)
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

    private var smallContent: some View {
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

    private var mediumContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if shouldShowStatus {
                statusLabel
            }

            Spacer(minLength: 0)

            if shouldShowInfo {
                infoContent(limit: mediumInfoLimit, compact: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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

            Spacer(minLength: 0)

            if shouldShowInfo {
                infoContent(limit: 3, compact: false)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
    private func infoContent(limit: Int, compact: Bool) -> some View {
        let page = selectedInfoPage

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
            ForEach(Array(entry.state.usedNewsTopics.prefix(limit))) { item in
                if let url = newsURL(item.url) {
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
        Text(item.title)
            .font((compact ? Font.callout : Font.title3).weight(.bold))
            .foregroundStyle(.white)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, compact ? 9 : 11)
            .background(Color.black.opacity(0.42))
            .clipShape(RoundedRectangle(cornerRadius: 10))
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
        entry.state.status == .processed && (!calendarEvents.isEmpty || !entry.state.usedNewsTopics.isEmpty)
    }

    private var shouldShowInfoPager: Bool {
        !calendarEvents.isEmpty && !entry.state.usedNewsTopics.isEmpty
    }

    private var mediumInfoLimit: Int {
        shouldShowInfoPager ? 1 : 2
    }

    private var calendarEvents: [WidgetCalendarEvent] {
        entry.state.usedCalendarEvents ?? []
    }

    private var selectedInfoPage: WidgetInfoPage {
        let storedPage = WidgetInfoPageStore.current()
        if storedPage == .calendar, !calendarEvents.isEmpty {
            return .calendar
        }
        if storedPage == .news, !entry.state.usedNewsTopics.isEmpty {
            return .news
        }
        if !calendarEvents.isEmpty {
            return .calendar
        }
        return .news
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

    private func newsURL(_ urlString: String?) -> URL? {
        guard let urlString,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        return url
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
    WondayWallWidgetEntry(date: Date(), state: .placeholder, image: nil)
}
