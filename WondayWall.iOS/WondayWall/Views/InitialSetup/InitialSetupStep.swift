import Foundation

// 初回セットアップのステップ
enum InitialSetupStep: Int, CaseIterable, Identifiable {
    case welcome
    case apiKey
    case calendar
    case rss
    case automaticGeneration
    case generation

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: return "ようこそ"
        case .apiKey: return "API キー"
        case .calendar: return "カレンダー"
        case .rss: return "ニュース"
        case .automaticGeneration: return "自動生成"
        case .generation: return "初回生成"
        }
    }

    var systemImage: String {
        switch self {
        case .welcome: return "sparkles"
        case .apiKey: return "key.fill"
        case .calendar: return "calendar"
        case .rss: return "newspaper"
        case .automaticGeneration: return "clock.arrow.circlepath"
        case .generation: return "photo.on.rectangle.angled"
        }
    }
}
