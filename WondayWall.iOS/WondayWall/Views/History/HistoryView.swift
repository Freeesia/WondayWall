import SwiftUI

// 履歴一覧画面
struct HistoryView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var viewModel: HistoryViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    HistoryContentView(vm: vm)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("履歴")
        }
        .task {
            if viewModel == nil {
                viewModel = HistoryViewModel(environment: environment)
            } else {
                viewModel?.loadHistory()
            }
        }
    }
}

// 履歴一覧のコンテンツ本体
private struct HistoryContentView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Bindable var vm: HistoryViewModel

    var body: some View {
        Group {
            if vm.items.isEmpty {
                ContentUnavailableView(
                    "履歴がありません",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("壁紙を生成すると履歴が表示されます")
                )
            } else {
                List {
                    ForEach(vm.items) { item in
                        NavigationLink {
                            HistoryPhotoPagerView(items: vm.items, initialItemID: item.id)
                                .environmentObject(environment)
                        } label: {
                            historyRow(item)
                        }
                    }
                    .onDelete { indexSet in
                        indexSet.forEach { vm.delete(vm.items[$0]) }
                    }
                }
            }
        }
        .toolbar {
            if !vm.items.isEmpty {
                EditButton()
            }
        }
    }

    @ViewBuilder
    private func historyRow(_ item: HistoryItem) -> some View {
        HStack(spacing: 12) {
            // サムネイル（成功時のみ表示）
            if item.isSuccess {
                HistoryThumbnailView(item: item)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: statusIcon(item))
                        .foregroundStyle(statusColor(item))
                        .font(.caption)
                    Text(statusLabel(item))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(statusColor(item))
                }
                Text(item.executedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(item.executedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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

    private func statusLabel(_ item: HistoryItem) -> String {
        if item.status == .generating { return "生成中" }
        if item.isSkipped { return "スキップ" }
        if item.isSuccess { return "成功" }
        return "失敗"
    }
}

// 履歴一覧のサムネイル表示（photoAssetId で Photos から非同期読み込み）
private struct HistoryThumbnailView: View {
    let item: HistoryItem
    @EnvironmentObject private var environment: AppEnvironment
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(.systemGray5)
            }
        }
        .task {
            if let assetId = item.photoAssetId {
                image = await environment.wallpaperService.loadImage(
                    assetId: assetId,
                    targetSize: CGSize(width: 112, height: 112)
                )
            }
        }
    }
}
