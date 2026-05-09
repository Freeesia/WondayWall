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
        }
    }
}

// ホーム画面のコンテンツ本体
private struct HomeContentView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.openURL) private var openURL
    var vm: HomeViewModel

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomTrailing) {
                // 最新壁紙を全画面背景として表示する（タブバー裏まで伸ばす）
                if let image = vm.latestImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                        .clipped()
                        .allowsHitTesting(false)
                }

                // スクロールコンテンツ（画像の上に重なる）
                ScrollView {
                    VStack(spacing: 0) {
                        if vm.latestImage != nil {
                            // 無の領域 — 背景画像を見せるための空白（画面の2/3）
                            Color.clear
                                .frame(height: geo.size.height * 2.0 / 3.0)
                        }

                        // コンテンツカード
                        VStack(spacing: 12) {
                            // 直近実行結果バッジ（成功時は表示しない）
                            if let history = vm.latestHistory, !history.isSuccess {
                                lastResultBadge(history: history)
                            }

                            // 最新生成で使用したニュース一覧
                            if let news = vm.latestHistory?.usedNewsTopics, !news.isEmpty {
                                usedNewsSection(news)
                            }
                        }
                        .padding()
                        .background(vm.latestImage != nil ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color.clear))
                        .frame(minHeight: geo.size.height * (vm.latestImage != nil ? 1.0 / 3.0 : 1.0), alignment: .top)

                        // FAB 分の下余白
                        Spacer().frame(height: 80)
                    }
                }
                .scrollContentBackground(.hidden)
                .alert("エラー", isPresented: Binding(
                    get: { vm.errorMessage != nil },
                    set: { if !$0 { vm.errorMessage = nil } }
                )) {
                    Button("OK") { vm.errorMessage = nil }
                } message: {
                    Text(vm.errorMessage ?? "")
                }
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

                // 壁紙生成フローティングボタン（右下固定）
                generateFloatButton
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    // 直近実行結果バッジ
    @ViewBuilder
    private func lastResultBadge(history: HistoryItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: statusIcon(history))
                .foregroundStyle(statusColor(history))
            Text(statusText(history))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(history.executedAt, style: .relative)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
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
            .background(Color(.systemGray5))
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
                        Label("生成！", systemImage: "sparkles")
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(environment.isGenerating)
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
