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
        ZStack(alignment: .top) {
            TabView(selection: $selectedItemID) {
                ForEach(items) { item in
                    HistoryPhotoPageView(item: item) {
                        detailItem = item
                    }
                    .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .top)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let currentItem {
                    HistoryPhotoHeaderView(item: currentItem) {
                        detailItem = currentItem
                    }
                }
            }
        }
        .sheet(item: $detailItem) { item in
            NavigationStack {
                HistoryDetailView(item: item)
                    .environmentObject(environment)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var currentItem: HistoryItem? {
        items.first { $0.id == selectedItemID }
    }
}

// 標準ナビゲーションバー上に表示する Liquid Glass 風タイトル
private struct HistoryPhotoHeaderView: View {
    let item: HistoryItem
    let onShowDetail: () -> Void

    private static let relativeDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            titleButton
        }
    }

    private var titleButton: some View {
        Button(action: onShowDetail) {
            VStack(alignment: .center, spacing: 2) {
                Text(Self.relativeDateFormatter.string(from: item.executedAt))
                    .font(.headline)
                    .lineLimit(1)
                Text(item.executedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
        }
        .frame(minWidth: 160, maxWidth: .infinity)
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Capsule())
        .accessibilityLabel("履歴詳細を表示")
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
            if let image {
                GeometryReader { geometry in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
            } else if item.isSuccess && !didFinishLoading {
                ProgressView()
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
                Text(item.executedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
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
