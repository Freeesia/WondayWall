import SwiftUI

// データ画面 — Google Calendar接続・カレンダー・ニュース・RSSソース・ユーザープロンプト
struct DataView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var viewModel: DataViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    DataContentView(vm: vm)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("データ")
        }
        .task {
            if viewModel == nil {
                viewModel = DataViewModel(environment: environment)
                await viewModel?.refresh()
            }
        }
    }
}

// データ画面のコンテンツ本体
private struct DataContentView: View {
    @EnvironmentObject private var environment: AppEnvironment
    var vm: DataViewModel

    var body: some View {
        List {
            // Google Calendar セクション
            Section {
                calendarConnectionRow
                if vm.calendarConnected {
                    calendarRows
                }
            } header: {
                Text("Google カレンダー")
            }

            // 直近予定セクション
            if !vm.upcomingEvents.isEmpty {
                Section {
                    ForEach(vm.upcomingEvents) { event in
                        calendarEventRow(event)
                    }
                } header: {
                    Text("直近の予定")
                }
            }

            // RSS ソースセクション
            Section {
                let sources = environment.configService.config.rssSources
                if sources.isEmpty {
                    Text("RSS ソースが設定されていません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sources, id: \.self) { source in
                        Text(source)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            } header: {
                Text("RSS ソース")
            }

            // ニュースセクション
            Section {
                if vm.isLoadingNews {
                    HStack {
                        ProgressView()
                        Text("取得中...")
                            .foregroundStyle(.secondary)
                    }
                } else if vm.recentNews.isEmpty {
                    Text("ニュースがありません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(vm.recentNews) { news in
                        newsRow(news)
                    }
                }
            } header: {
                Text("取得ニュース (\(vm.recentNews.count)件)")
            }

            // ユーザープロンプトセクション
            Section {
                let prompt = environment.configService.config.userPrompt
                if prompt.isEmpty {
                    Text("プロンプトが設定されていません")
                        .foregroundStyle(.secondary)
                } else {
                    Text(prompt)
                }
            } header: {
                Text("ユーザープロンプト")
            }
        }
        .refreshable {
            await vm.refresh()
        }
        .alert("エラー", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // カレンダー接続状態行
    @ViewBuilder
    private var calendarConnectionRow: some View {
        HStack {
            Image(systemName: vm.calendarConnected ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(vm.calendarConnected ? .green : .red)
            Text(vm.calendarConnected ? "接続済み" : "未接続")
        }
    }

    // 取得対象カレンダー一覧
    @ViewBuilder
    private var calendarRows: some View {
        let selected = environment.configService.config.targetCalendarIds
        if selected.isEmpty {
            Text("カレンダーが選択されていません")
                .foregroundStyle(.secondary)
        } else {
            ForEach(vm.availableCalendars.filter { selected.contains($0.id) }) { calendar in
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(.blue)
                    Text(calendar.summary)
                    if calendar.isPrimary {
                        Spacer()
                        Text("プライマリ")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // カレンダーイベント行
    @ViewBuilder
    private func calendarEventRow(_ event: CalendarEventItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.title)
                .font(.body)
            HStack {
                Text(event.startTime, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let location = event.location {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // ニュース行
    @ViewBuilder
    private func newsRow(_ news: NewsTopicItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(news.title)
                .font(.body)
                .lineLimit(2)
            HStack {
                Text(news.publishedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let summary = news.summary {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
