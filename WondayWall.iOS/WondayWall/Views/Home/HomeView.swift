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
            .navigationTitle("WondayWall")
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
    var vm: HomeViewModel

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 20) {
                    // 最新生成画像プレビュー
                    wallpaperPreview

                    // 直近実行結果バッジ
                    if let history = vm.latestHistory {
                        lastResultBadge(history: history)
                    }

                    // 壁紙の設定方法ボタン（画像ありのときのみ表示）
                    if vm.latestImage != nil {
                        Button {
                            vm.showWallpaperInstructions()
                        } label: {
                            Label("壁紙の設定方法", systemImage: "info.circle")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(14)
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .padding()
                // フローティングボタン分の下余白を確保する
                .padding(.bottom, 80)
            }
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

            // 今すぐ生成フローティングボタン（右下固定）
            generateFloatButton
                .padding(.trailing, 24)
                .padding(.bottom, 24)
        }
    }

    // 最新壁紙プレビュー
    @ViewBuilder
    private var wallpaperPreview: some View {
        if let image = vm.latestImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .cornerRadius(16)
                .shadow(radius: 8)
        }
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

    // 今すぐ生成フローティングボタン
    @ViewBuilder
    private var generateFloatButton: some View {
        Button {
            Task { await vm.generate() }
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
                    Text("今すぐ生成")
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

    // 今すぐ生成ボタン（旧コード削除済み）

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
