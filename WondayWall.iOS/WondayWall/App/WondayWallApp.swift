import SwiftUI

@main
struct WondayWallApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(environment)
        }
    }
}
