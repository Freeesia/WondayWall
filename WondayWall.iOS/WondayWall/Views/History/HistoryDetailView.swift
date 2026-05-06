import SwiftUI

// 履歴詳細画面 — 画像プレビュー・使用データ・アクション
struct HistoryDetailView: View {
    let item: HistoryItem
    @EnvironmentObject private var environment: AppEnvironment
    @State private var isRegenerating = false
    @State private var errorMessage: String?
    // Photos から非同期読み込まれた画像
    @State private var loadedImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 画像プレビュー
                if item.isSuccess {
                    imagePreview
                }

                // ステータスバッジ
                statusBadge

                // アクションボタン群
                if loadedImage != nil && item.isSuccess {
                    actionButtons
                }

                // 使用した予定
                if let events = item.usedCalendarEvents, !events.isEmpty {
                    usedEventsSection(events)
                }

                // 使用したニュース
                if let news = item.usedNewsTopics, !news.isEmpty {
                    usedNewsSection(news)
                }

                // 使用したプロンプト
                if let prompt = item.usedPrompt, !prompt.isEmpty {
                    usedPromptSection(prompt)
                }

                // エラー詳細
                if let error = item.errorSummary {
                    errorSection(error)
                }
            }
            .padding()
        }
        .navigationTitle(item.executedAt.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task<Void, Never> { @MainActor in await self.loadImage() }
        }
        .alert("エラー", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // 画像プレビュー
    @ViewBuilder
    private var imagePreview: some View {
        if let image = loadedImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .cornerRadius(16)
                .shadow(radius: 8)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray5))
                    .aspectRatio(9.0 / 19.5, contentMode: .fit)
                Image(systemName: "photo.slash")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // ステータスバッジ
    @ViewBuilder
    private var statusBadge: some View {
        HStack {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
            Text(statusLabel)
                .fontWeight(.semibold)
                .foregroundStyle(statusColor)
            Spacer()
            Text(item.executedAt, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    // アクションボタン群
    @ViewBuilder
    private var actionButtons: some View {
        // 同じ条件で再生成
        Button {
            Task {
                isRegenerating = true
                defer { isRegenerating = false }
                let result = await environment.coordinator.runManual()
                if !result.isSuccess {
                    errorMessage = result.errorSummary ?? "再生成に失敗しました"
                } else {
                    dismiss()
                }
            }
        } label: {
            HStack {
                if isRegenerating { ProgressView().tint(.white) }
                Text(isRegenerating ? "生成中..." : "同じ条件で再生成")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isRegenerating ? Color.gray : Color.accentColor)
            .foregroundStyle(.white)
            .cornerRadius(14)
        }
        .disabled(isRegenerating)
    }

    // 使用した予定セクション
    @ViewBuilder
    private func usedEventsSection(_ events: [CalendarEventItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("使用した予定", systemImage: "calendar")
                .font(.headline)
            VStack(spacing: 0) {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 12)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title).font(.subheadline)
                        Text(event.startTime, style: .date).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 使用したニュースセクション
    @ViewBuilder
    private func usedNewsSection(_ news: [NewsTopicItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("使用したニュース", systemImage: "newspaper")
                .font(.headline)
            VStack(spacing: 0) {
                ForEach(Array(news.enumerated()), id: \.element.id) { index, newsItem in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 44)
                    }
                    let row = newsRowContent(newsItem)
                    if let urlString = newsItem.url, let url = URL(string: urlString) {
                        Button { openURL(url) } label: { row }
                            .foregroundStyle(.primary)
                    } else {
                        row
                    }
                }
            }
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func newsRowContent(_ item: NewsTopicItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            FaviconImage(urlString: item.url)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline)
                    .lineLimit(2)
                Text(item.publishedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 使用したプロンプトセクション
    @ViewBuilder
    private func usedPromptSection(_ prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("使用したプロンプト", systemImage: "text.quote")
                .font(.headline)
            Text(prompt)
                .font(.body)
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // エラーセクション
    @ViewBuilder
    private func errorSection(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("エラー詳細", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(.red)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusIcon: String {        if item.isSkipped { return "minus.circle" }
        if item.isSuccess { return "checkmark.circle.fill" }
        return "xmark.circle.fill"
    }

    // Photos から画像を非同期読み込む
    private func loadImage() async {
        guard item.isSuccess, let assetId = item.photoAssetId else { return }
        loadedImage = await environment.wallpaperService.loadImage(assetId: assetId)
    }

    private var statusColor: Color {
        if item.isSkipped { return .gray }
        if item.isSuccess { return .green }
        return .red
    }

    private var statusLabel: String {
        if item.isSkipped { return "スキップ" }
        if item.isSuccess { return "成功" }
        return "失敗"
    }
}
