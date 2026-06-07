import Photos
import SwiftUI
import UIKit
import WidgetKit

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
        switch family {
        case .systemSmall:
            smallContent
        case .systemLarge:
            largeContent
        default:
            mediumContent
        }
    }

    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer()
            if shouldShowStatus {
                statusLabel
                if entry.state.canOpenGenerationConfirmation {
                    generateLink(compact: true)
                }
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
        HStack(spacing: 12) {
            if shouldShowStatus {
                VStack(alignment: .leading, spacing: 8) {
                    statusLabel
                    if entry.state.canOpenGenerationConfirmation {
                        generateLink(compact: false)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: 116, alignment: .leading)
            }

            if shouldShowNews {
                newsList(limit: 2)
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
                        if entry.state.canOpenGenerationConfirmation {
                            generateLink(compact: false)
                        }
                    }
                    Spacer()
                }
            }

            Spacer(minLength: 0)

            if shouldShowNews {
                newsList(limit: 3)
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
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text(compact ? "生成" : "壁紙生成")
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, compact ? 6 : 8)
            .background(Color.accentColor)
            .clipShape(Capsule())
        }
    }

    private func newsList(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(entry.state.usedNewsTopics.prefix(limit))) { item in
                if let urlString = item.url, let url = URL(string: urlString) {
                    Link(destination: url) {
                        newsRow(item)
                    }
                } else {
                    newsRow(item)
                }
            }
        }
    }

    private func newsRow(_ item: WidgetNewsTopic) -> some View {
        Text(item.title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.white)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.32))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var statusText: String {
        switch entry.state.status {
        case .unconfigured:
            return "初期設定が必要です"
        case .pending:
            return "未実行スロット"
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
        entry.state.status != .processed
    }

    private var shouldShowNews: Bool {
        entry.state.status == .processed && !entry.state.usedNewsTopics.isEmpty
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

    @ViewBuilder
    private var overlayScrim: some View {
        if shouldShowStatus || shouldShowNews {
            bottomScrim
        }
    }

    private var bottomScrim: LinearGradient {
        LinearGradient(
            colors: [.clear, Color.black.opacity(shouldShowNews ? 0.42 : 0.68)],
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
