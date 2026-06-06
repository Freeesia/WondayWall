import SwiftUI
import UIKit
import WidgetKit

struct WondayWallWidgetEntry: TimelineEntry {
    let date: Date
    let state: WidgetSharedState
}

struct WondayWallWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WondayWallWidgetEntry {
        WondayWallWidgetEntry(date: Date(), state: .placeholder)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (WondayWallWidgetEntry) -> Void
    ) {
        completion(WondayWallWidgetEntry(date: Date(), state: loadState() ?? .placeholder))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<WondayWallWidgetEntry>) -> Void
    ) {
        let state = loadState() ?? .placeholder
        let entry = WondayWallWidgetEntry(date: Date(), state: state)
        let refreshDate = state.nextSlotStartsAt ?? Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }

    private func loadState() -> WidgetSharedState? {
        guard let url = WidgetSharedConstants.stateFileURL(),
              let data = try? Data(contentsOf: url)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSharedState.self, from: data)
    }
}

struct WondayWallWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WondayWallWidgetEntry

    var body: some View {
        ZStack {
            wallpaperBackground
            overlayContent
        }
        .containerBackground(for: .widget) {
            Color(.secondarySystemBackground)
        }
    }

    @ViewBuilder
    private var wallpaperBackground: some View {
        if let image = thumbnailImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            statusLabel
            if entry.state.canOpenGenerationConfirmation {
                generateLink(compact: true)
            } else if let date = entry.state.latestDisplayHistory?.executedAt {
                Text(date, style: .time)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background(bottomScrim)
    }

    private var mediumContent: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                statusLabel
                if entry.state.canOpenGenerationConfirmation {
                    generateLink(compact: false)
                } else {
                    lastGeneratedText
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: 116, alignment: .leading)

            if entry.state.status == .processed {
                newsList(limit: 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(sideScrim)
    }

    private var largeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    statusLabel
                    if entry.state.canOpenGenerationConfirmation {
                        generateLink(compact: false)
                    } else {
                        lastGeneratedText
                    }
                }
                Spacer()
            }

            Spacer(minLength: 0)

            if entry.state.status == .pending,
               let nextSlot = entry.state.nextSlotStartsAt {
                Text("次回 \(nextSlot.formatted(date: .omitted, time: .shortened))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
            }

            if entry.state.status == .processed {
                newsList(limit: 3)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(bottomScrim)
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

    private var lastGeneratedText: some View {
        Group {
            if let date = entry.state.latestDisplayHistory?.executedAt {
                Text("最終生成 \(date.formatted(date: .omitted, time: .shortened))")
            } else {
                Text("履歴はまだありません")
            }
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.white.opacity(0.9))
        .lineLimit(1)
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
            return "実行済み"
        case .generating:
            if let progress = entry.state.generationProgress {
                return "生成中 \(progress)%"
            }
            return "生成中"
        }
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

    private var thumbnailImage: UIImage? {
        guard let fileName = entry.state.latestDisplayHistory?.thumbnailFileName,
              let url = WidgetSharedConstants.thumbnailURL(fileName: fileName)
        else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private var bottomScrim: LinearGradient {
        LinearGradient(
            colors: [.clear, Color.black.opacity(0.68)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var sideScrim: LinearGradient {
        LinearGradient(
            colors: [Color.black.opacity(0.68), Color.black.opacity(0.18), .clear],
            startPoint: .leading,
            endPoint: .trailing
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
    }
}

#Preview(as: .systemMedium) {
    WondayWallWidget()
} timeline: {
    WondayWallWidgetEntry(date: Date(), state: .placeholder)
}
