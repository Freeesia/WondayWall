import SwiftUI

// タブビュー — Home / Data / History / Settings の4タブ構成
struct ContentView: View {
    @State private var selectedTab = 0
    // フォアグラウンド中の生成成功 Toast 表示フラグ
    @State private var showSuccessToast = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
                HomeView()
                    .tabItem {
                        Label("ホーム", systemImage: "house.fill")
                    }
                    .tag(0)
                DataView()
                    .tabItem {
                        Label("データ", systemImage: "calendar.badge.clock")
                    }
                    .tag(1)
                HistoryView()
                    .tabItem {
                        Label("履歴", systemImage: "clock.arrow.circlepath")
                    }
                    .tag(2)
                SettingsView()
                    .tabItem {
                        Label("設定", systemImage: "gearshape.fill")
                    }
                    .tag(3)
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .openHistoryNotification)
            ) { _ in
                // 通知タップ時に履歴タブへ遷移する
                selectedTab = 2
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .generationSucceededInForeground)
            ) { _ in
                // フォアグラウンド中のみ Toast を表示する
                guard scenePhase == .active else { return }
                withAnimation {
                    showSuccessToast = true
                }
            }

            // 生成成功 Toast（上部に重ねて表示）
            if showSuccessToast {
                ToastView(message: "壁紙を生成しました。タップして確認") {
                    withAnimation { showSuccessToast = false }
                    // ホームタブの先頭へ遷移する
                    selectedTab = 0
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(999)
                .onAppear {
                    Task {
                        try? await Task.sleep(for: .seconds(4))
                        withAnimation { showSuccessToast = false }
                    }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showSuccessToast)
    }
}

// アプリ内 Toast バナー表示コンポーネント
private struct ToastView: View {
    let message: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(radius: 6)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppEnvironment())
}
