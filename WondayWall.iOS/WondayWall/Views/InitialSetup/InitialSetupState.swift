import Foundation

// 初回セットアップの処理状態
enum InitialSetupState {
    case editing
    case requestingCalendar
    case resolvingRss
    case requestingPhotos
    case requestingNotifications
    case loadingGenerationPreview
    case saving
    case generating
    case completed

    var isBusy: Bool {
        switch self {
        case .editing, .completed:
            return false
        case .requestingCalendar, .resolvingRss, .requestingPhotos,
             .requestingNotifications, .loadingGenerationPreview, .saving, .generating:
            return true
        }
    }

    var statusText: String? {
        switch self {
        case .editing:
            return nil
        case .requestingCalendar:
            return "カレンダーアクセスを確認しています..."
        case .resolvingRss:
            return "RSS フィードを確認しています..."
        case .requestingPhotos:
            return "写真ライブラリのアクセス権を確認しています..."
        case .requestingNotifications:
            return "通知権限を確認しています..."
        case .loadingGenerationPreview:
            return "使用する予定とニュースを確認しています..."
        case .saving:
            return "設定を保存しています..."
        case .generating:
            return "最初の壁紙を生成しています..."
        case .completed:
            return "初回セットアップが完了しました。"
        }
    }
}
