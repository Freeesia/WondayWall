import SwiftUI

// 履歴を写真アプリ風に左右スワイプで切り替えるビュー
struct HistoryPhotoPagerView: View {
    let items: [HistoryItem]

    @EnvironmentObject private var environment: AppEnvironment
    @State private var selectedItemID: UUID
    @State private var detailItem: HistoryItem?

    init(items: [HistoryItem], initialItemID: UUID) {
        self.items = items
        _selectedItemID = State(initialValue: initialItemID)
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            TabView(selection: $selectedItemID) {
                ForEach(items) { item in
                    HistoryPhotoPageView(item: item) {
                        detailItem = item
                    }
                    .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationTitle(currentTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(item: $detailItem) { item in
            NavigationStack {
                HistoryDetailView(item: item)
                    .environmentObject(environment)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var currentTitle: String {
        guard let item = items.first(where: { $0.id == selectedItemID }) else {
            return "履歴"
        }
        return item.executedAt.formatted(date: .abbreviated, time: .omitted)
    }
}

// 1件分の履歴画像またはプレースホルダーを表示する
private struct HistoryPhotoPageView: View {
    let item: HistoryItem
    let onShowDetail: () -> Void

    @EnvironmentObject private var environment: AppEnvironment
    @State private var image: UIImage?
    @State private var didFinishLoading = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if item.isSuccess && !didFinishLoading {
                ProgressView()
                    .tint(.white)
            } else {
                placeholder
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(detailSwipeGesture)
        .task(id: item.id) {
            await loadImage()
        }
    }

    private var detailSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let width = abs(value.translation.width)
                let height = abs(value.translation.height)
                guard value.translation.height < -72, height > width * 1.4 else { return }
                onShowDetail()
            }
    }

    private var placeholder: some View {
        VStack(spacing: 16) {
            Image(systemName: statusIcon)
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(statusColor)

            VStack(spacing: 6) {
                Text(statusLabel)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                Text(item.executedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func loadImage() async {
        image = nil
        didFinishLoading = false

        guard item.isSuccess, let assetId = item.photoAssetId else {
            didFinishLoading = true
            return
        }

        image = await environment.wallpaperService.loadImage(assetId: assetId)
        didFinishLoading = true
    }

    private var statusIcon: String {
        if item.isSkipped { return "minus.circle" }
        if item.isGenerating { return "hourglass.circle" }
        if item.isSuccess { return "photo.slash" }
        return "xmark.circle.fill"
    }

    private var statusColor: Color {
        if item.isSkipped { return .gray }
        if item.isGenerating { return .orange }
        if item.isSuccess { return .white.opacity(0.72) }
        return .red
    }

    private var statusLabel: String {
        if item.isSkipped { return "スキップ" }
        if item.isGenerating { return "生成中" }
        if item.isSuccess { return "画像を読み込めません" }
        return "失敗"
    }
}
