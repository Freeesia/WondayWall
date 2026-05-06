import SwiftUI

// タブビュー — Home / Data / History / Settings の4タブ構成
struct ContentView: View {
    @State private var selectedTab = 0
    // 通知タップ時に履歴タブへ遷移するため管理する

    var body: some View {
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
    }
}

#Preview {
    ContentView()
        .environmentObject(AppEnvironment())
}
