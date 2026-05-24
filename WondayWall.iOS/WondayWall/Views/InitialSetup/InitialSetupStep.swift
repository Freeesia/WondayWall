import Foundation

// 初回セットアップのステップ
enum InitialSetupStep: Int, CaseIterable, Identifiable {
    case welcome
    case apiKey
    case calendar
    case context
    case automaticGeneration
    case generation
    case wallpaperInstructions

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: return "ようこそ"
        case .apiKey: return "API キー"
        case .calendar: return "カレンダー"
        case .context: return "コンテキスト"
        case .automaticGeneration: return "自動生成"
        case .generation: return "初回生成"
        case .wallpaperInstructions: return "壁紙設定"
        }
    }

    var systemImage: String {
        switch self {
        case .welcome: return "sparkles"
        case .apiKey: return "key.fill"
        case .calendar: return "calendar"
        case .context: return "text.bubble"
        case .automaticGeneration: return "clock.arrow.circlepath"
        case .generation: return "photo.on.rectangle.angled"
        case .wallpaperInstructions: return "hand.tap"
        }
    }
}
