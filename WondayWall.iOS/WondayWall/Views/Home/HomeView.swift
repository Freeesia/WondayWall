import SwiftUI

// ホーム画面 — 最新壁紙プレビュー・生成ボタン・アクション
struct HomeView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var viewModel: HomeViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    HomeContentView(vm: vm)
                } else {
                    ProgressView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel?.showWallpaperInstructions()
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
        }
        .task {
            if viewModel == nil {
                viewModel = HomeViewModel(environment: environment)
            }
            if let slotStartedAt = environment.pendingWidgetGenerationSlotStartedAt {
                await handleWidgetGenerationRequest(slotStartedAt)
            }
        }
        .onReceive(environment.$pendingWidgetGenerationSlotStartedAt) { slotStartedAt in
            guard let slotStartedAt else { return }
            Task {
                await handleWidgetGenerationRequest(slotStartedAt)
            }
        }
    }

    @MainActor
    private func handleWidgetGenerationRequest(_ slotStartedAt: Date) async {
        guard let viewModel else { return }
        await viewModel.openGenerationSheetIfStillAllowed(slotStartedAt: slotStartedAt)
        environment.clearWidgetGenerationConfirmationRequest()
    }
}

// ホーム画面のコンテンツ本体
private struct HomeContentView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.openURL) private var openURL
    var vm: HomeViewModel

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    if vm.latestImage != nil {
                        // 無の領域 — 背景画像を見せるための空白（画面の2/3）
                        Color.clear
                            .frame(height: geo.size.height * 2.0 / 3.0)
                    }

                    // コンテンツカード
                    // 最新生成で使用した予定一覧
                    if let events = vm.latestHistory?.usedCalendarEvents, !events.isEmpty {
                        LinearGradient(colors: [.clear, Color(.systemGray5).opacity(0.8)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 24)
                            .frame(maxWidth: .infinity)
                            .allowsHitTesting(false)
                        usedEventsSection(events)
                            .padding(.horizontal)
                            .background(LinearGradient(colors: [Color(.systemGray5).opacity(0.8), .clear], startPoint: .top, endPoint: .bottom))
                    }
                    // 最新生成で使用したニュース一覧
                    if let news = vm.latestHistory?.usedNewsTopics, !news.isEmpty {
                        LinearGradient(colors: [.clear, Color(.systemGray5).opacity(0.8)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 24)
                            .frame(maxWidth: .infinity)
                            .allowsHitTesting(false)
                        usedNewsSection(news)
                            .padding(.horizontal)
                            .background(LinearGradient(colors: [Color(.systemGray5).opacity(0.8), .clear], startPoint: .top, endPoint: .bottom))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollContentBackground(.hidden)
            .sheet(isPresented: Binding(
                get: { vm.showInstructions },
                set: { vm.showInstructions = $0 }
            )) {
                WallpaperInstructionsView()
            }
            .sheet(isPresented: Binding(
                get: { vm.showGenerationSheet },
                set: { vm.showGenerationSheet = $0 }
            )) {
                GenerationConfirmSheet(vm: vm)
            }
            .background{
                // 最新壁紙を全画面背景として表示する（タブバー裏まで伸ばす）
                if let image = vm.latestImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea(.container, edges: .all)
                } else {
                    ZStack() {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemGray5))
                        VStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text("まだ壁紙がありません")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                }
            }
            .safeAreaInset(edge: .bottom) {
                // 壁紙生成フローティングボタン（右下固定）
                generateFloatButton
                    .padding(.trailing, 24)
                    .padding(.bottom, 12)
            }
        }
    }

    // 使用した予定セクション
    @ViewBuilder
    private func usedEventsSection(_ events: [CalendarEventItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
                        HStack {
                            if event.isAllDay {
                                Text(event.startTime, style: .date)
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("終日")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text(event.startTime, style: .date)
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(event.startTime, style: .time)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(AnyShapeStyle(.regularMaterial))
            .cornerRadius(10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 使用したニュース一覧
    @ViewBuilder
    private func usedNewsSection(_ news: [NewsTopicItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("使用したニュース", systemImage: "newspaper")
                .font(.headline)
            VStack(spacing: 0) {
                ForEach(Array(news.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().padding(.leading, 44) }
                    let row = newsRow(item)
                    if let urlString = item.url, let url = URL(string: urlString) {
                        Button { openURL(url) } label: { row }
                            .foregroundStyle(.primary)
                    } else {
                        row
                    }
                }
            }
            .background(AnyShapeStyle(.regularMaterial))
            .cornerRadius(10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func newsRow(_ item: NewsTopicItem) -> some View {
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

    // 壁紙生成フローティングボタン
    @ViewBuilder
    private var generateFloatButton: some View {
        Button {
            if !environment.isGenerating {
                vm.showGenerationSheet = true
            }
        } label: {
            HStack(spacing: 6) {
                if environment.isGenerating {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 20, height: 20)
                    Text("生成中...")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("壁紙生成")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(environment.isGenerating ? Color.gray : Color.accentColor)
            .clipShape(Capsule())
            .shadow(radius: 6)
        }
        .disabled(environment.isGenerating)
    }

    private func statusIcon(_ item: HistoryItem) -> String {
        if item.status == .generating { return "hourglass" }
        if item.isSkipped { return "minus.circle" }
        if item.isSuccess { return "checkmark.circle.fill" }
        return "xmark.circle.fill"
    }

    private func statusColor(_ item: HistoryItem) -> Color {
        if item.status == .generating { return .orange }
        if item.isSkipped { return .gray }
        if item.isSuccess { return .green }
        return .red
    }

    private func statusText(_ item: HistoryItem) -> String {
        if item.status == .generating { return "生成中..." }
        if item.isSkipped { return "前回: スキップ" }
        if item.isSuccess { return "前回: 生成成功" }
        return "前回: 失敗"
    }
}

// 壁紙生成確認シート — 使用予定データを確認してから生成を実行する
private struct GenerationConfirmSheet: View {
    @EnvironmentObject private var environment: AppEnvironment
    var vm: HomeViewModel

    var body: some View {
        NavigationStack {
            List {
                // カレンダー予定セクション
                if !vm.sheetEvents.isEmpty {
                    Section("カレンダー予定") {
                        ForEach(vm.sheetEvents) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.title).font(.body)
                                HStack {
                                    if event.isAllDay {
                                        Text(event.startTime, style: .date)
                                            .font(.caption).foregroundStyle(.secondary)
                                        Text("終日")
                                            .font(.caption).foregroundStyle(.secondary)
                                    } else {
                                        Text(event.startTime, style: .date)
                                            .font(.caption).foregroundStyle(.secondary)
                                        Text(event.startTime, style: .time)
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                // ニュースセクション
                if !vm.sheetNews.isEmpty {
                    Section("ニュース") {
                        ForEach(vm.sheetNews) { item in
                            HStack(alignment: .top, spacing: 8) {
                                FaviconImage(urlString: item.url)
                                    .padding(.top, 2)
                                Text(item.title)
                                    .font(.subheadline)
                                    .lineLimit(2)
                            }
                        }
                    }
                }

                // データなし
                if vm.sheetEvents.isEmpty && vm.sheetNews.isEmpty && !vm.isLoadingSheetData {
                    Section {
                        Text("利用できるカレンダー予定・ニュースがありません")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .overlay {
                if vm.isLoadingSheetData {
                    ProgressView()
                }
            }
            .navigationTitle("壁紙を生成する")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { vm.showGenerationSheet = false }
                }
                ToolbarItem(placement: .status) {
                    Button {
                        Task { await vm.generate() }
                    } label: {
                        HStack(spacing: 6) {
                            if vm.isLoadingSheetData {
                                // ニュース取得中はビジーアイコンを表示する
                                ProgressView()
                                    .tint(.white)
                                    .frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text("生成！")
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(environment.isGenerating || vm.isLoadingSheetData)
                    .controlSize(.large)
                }
            }
        }
        .task { await vm.loadSheetData() }
    }
}

// UIActivityViewController の SwiftUI ラッパー
struct ActivityViewControllerRepresentable: UIViewControllerRepresentable {
    let controller: UIActivityViewController
    func makeUIViewController(context: Context) -> UIActivityViewController { controller }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// 壁紙設定手順シート
struct WallpaperInstructionsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(environment.wallpaperService.wallpaperInstructions())
                    .padding()
                    .font(.body)
            }
            .navigationTitle("壁紙の設定方法")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}
