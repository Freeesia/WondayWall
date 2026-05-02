import SwiftUI

@main
struct WondayWallApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(environment)
                .task {
                    // アプリ起動時にバックグラウンド生成の取りこぼし補完を実行する
                    await environment.backgroundTaskService.checkAndRunIfNeeded()
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.willEnterForegroundNotification
                    )
                ) { _ in
                    // フォアグラウンド復帰時にも生成可否チェックを行う
                    Task {
                        await environment.backgroundTaskService.checkAndRunIfNeeded()
                    }
                }
        }
    }
}
