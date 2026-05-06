import Foundation

// Gemini API の推論階層
// Flex: 標準より 50% 安価だが、レイテンシが変動しベスト・エフォート型
// Standard: 通常料金、低レイテンシ・高信頼性
enum GoogleAiServiceTier: String {
    case standard
    case flex
}
