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
                            HistoryDetailView(item: item)
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
        .alert("エラー", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func historyRow(_ item: HistoryItem) -> some View {
        HStack(spacing: 12) {
            // サムネイル（成功時のみ表示）
            if item.isSuccess,
               let path = item.imagePath,
               FileManager.default.fileExists(atPath: path),
               let image = UIImage(contentsOfFile: path)
            {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
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
        if item.isSkipped { return "minus.circle" }
        if item.isSuccess { return "checkmark.circle.fill" }
        return "xmark.circle.fill"
    }

    private func statusColor(_ item: HistoryItem) -> Color {
        if item.isSkipped { return .gray }
        if item.isSuccess { return .green }
        return .red
    }

    private func statusLabel(_ item: HistoryItem) -> String {
        if item.isSkipped { return "スキップ" }
        if item.isSuccess { return "成功" }
        return "失敗"
    }
}
