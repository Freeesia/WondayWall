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
        ScrollView {
            VStack(spacing: 20) {
                // アクションボタン群
                actionButtons

                // 直近実行結果バッジ
                if let history = vm.latestHistory {
                    lastResultBadge(history: history)
                }

                // 最新生成画像プレビュー
                wallpaperPreview
            }
            .padding()
        }
        .alert("エラー", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .alert("保存完了", isPresented: Binding(
            get: { vm.showSaveSuccess },
            set: { vm.showSaveSuccess = $0 }
        )) {
            Button("OK") {}
        } message: {
            Text("写真ライブラリに保存しました。")
        }
        .sheet(isPresented: Binding(
            get: { vm.showShareSheet },
            set: { vm.showShareSheet = $0 }
        )) {
            if let path = vm.latestImagePath,
               let ctrl = environment.wallpaperService.makeShareController(imagePath: path)
            {
                ActivityViewControllerRepresentable(controller: ctrl)
            }
        }
        .sheet(isPresented: Binding(
            get: { vm.showInstructions },
            set: { vm.showInstructions = $0 }
        )) {
            WallpaperInstructionsView()
        }
    }

    // 最新壁紙プレビュー
    @ViewBuilder
    private var wallpaperPreview: some View {
        if let path = vm.latestImagePath, let image = UIImage(contentsOfFile: path) {
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
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("まだ壁紙がありません")
                        .foregroundStyle(.secondary)
                }
            }
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

    // アクションボタン群
    @ViewBuilder
    private var actionButtons: some View {
        // 今すぐ生成ボタン
        Button {
            Task { await vm.generate() }
        } label: {
            HStack {
                if vm.isGenerating {
                    ProgressView()
                        .tint(.white)
                }
                Text(vm.isGenerating ? "生成中..." : "今すぐ生成")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(vm.isGenerating ? Color.gray : Color.accentColor)
            .foregroundStyle(.white)
            .cornerRadius(14)
        }
        .disabled(vm.isGenerating)

        // 写真に保存・共有・壁紙設定手順
        if vm.latestImagePath != nil {
            HStack(spacing: 12) {
                Button {
                    Task { await vm.saveToPhotos() }
                } label: {
                    Label("写真に保存", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(14)
                }
                .foregroundStyle(.primary)

                Button {
                    vm.showShareSheet = true
                } label: {
                    Label("共有", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(14)
                }
                .foregroundStyle(.primary)
            }

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

    private func statusText(_ item: HistoryItem) -> String {
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
