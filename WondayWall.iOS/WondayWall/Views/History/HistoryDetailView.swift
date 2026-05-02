import SwiftUI

// 履歴詳細画面 — 画像プレビュー・使用データ・アクション
struct HistoryDetailView: View {
    let item: HistoryItem
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showShareSheet = false
    @State private var showSaveSuccess = false
    @State private var isRegenerating = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 画像プレビュー
                imagePreview

                // ステータスバッジ
                statusBadge

                // アクションボタン群
                if item.imagePath != nil && item.isSuccess {
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
        .navigationTitle(item.executedAt, style: .date)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            if let path = item.imagePath,
               let ctrl = environment.wallpaperService.makeShareController(imagePath: path) {
                ActivityViewControllerRepresentable(controller: ctrl)
            }
        }
        .alert("保存完了", isPresented: $showSaveSuccess) {
            Button("OK") {}
        } message: {
            Text("写真ライブラリに保存しました。")
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
        if let path = item.imagePath,
           FileManager.default.fileExists(atPath: path),
           let image = UIImage(contentsOfFile: path)
        {
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
        HStack(spacing: 12) {
            Button {
                Task {
                    guard let path = item.imagePath else { return }
                    do {
                        try await environment.wallpaperService.saveToPhotos(imagePath: path)
                        showSaveSuccess = true
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            } label: {
                Label("写真に保存", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(14)
                    .foregroundStyle(.primary)
            }

            Button { showShareSheet = true } label: {
                Label("共有", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(14)
                    .foregroundStyle(.primary)
            }
        }

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
        VStack(alignment: .leading, spacing: 8) {
            Label("使用した予定", systemImage: "calendar")
                .font(.headline)
            ForEach(events) { event in
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title).font(.subheadline)
                    Text(event.startTime, style: .date).font(.caption).foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 使用したニュースセクション
    @ViewBuilder
    private func usedNewsSection(_ news: [NewsTopicItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("使用したニュース", systemImage: "newspaper")
                .font(.headline)
            ForEach(news) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.subheadline).lineLimit(2)
                    Text(item.publishedAt, style: .relative)
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
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

    private var statusIcon: String {
        if item.isSkipped { return "minus.circle" }
        if item.isSuccess { return "checkmark.circle.fill" }
        return "xmark.circle.fill"
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
