import Foundation
import Network

// ネットワーク状態を確認するユーティリティ
// NWPathMonitor を使って現在のネットワーク接続タイプを判定する
enum NetworkHelper {
    // Wi-Fi（または有線）接続かどうかを同期的に確認する
    // NWPathMonitor を一時的に使用してスナップショットを取得する
    static func isOnWiFi() -> Bool {
        let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
        var connected = false
        let semaphore = DispatchSemaphore(value: 0)
        let queue = DispatchQueue(label: "com.studiofreesia.wondaywall.network-check")
        monitor.pathUpdateHandler = { path in
            connected = path.status == .satisfied
            semaphore.signal()
        }
        monitor.start(queue: queue)
        // タイムアウト付きで待機（通常は即時に値が返る）
        _ = semaphore.wait(timeout: .now() + 1.0)
        monitor.cancel()
        return connected
    }

    // セルラーを含む任意の通信が可能かどうかを確認する
    static func isNetworkAvailable() -> Bool {
        let monitor = NWPathMonitor()
        var available = false
        let semaphore = DispatchSemaphore(value: 0)
        let queue = DispatchQueue(label: "com.studiofreesia.wondaywall.network-avail-check")
        monitor.pathUpdateHandler = { path in
            available = path.status == .satisfied
            semaphore.signal()
        }
        monitor.start(queue: queue)
        _ = semaphore.wait(timeout: .now() + 1.0)
        monitor.cancel()
        return available
    }
}
