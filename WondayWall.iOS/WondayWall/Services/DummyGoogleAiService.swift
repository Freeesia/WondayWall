import Foundation
import UIKit

#if DEBUG
// 実 API を使わずに遅延付きで動作を再現するダミー実装（DEBUG ビルド専用）
final class DummyGoogleAiService: GoogleAiServiceProtocol {
    private let configService: AppConfigService

    init(configService: AppConfigService) {
        self.configService = configService
    }

    func generatePrompt(
        context: PromptContext,
        serviceTier _: GoogleAiServiceTier,
        onProgress: ((Double, String) -> Void)? = nil
    ) async throws -> PromptGenerationResult {
        let promptDelay = UInt64(configService.debugConfig.dummyPromptDelaySeconds)
        try await simulateProgress(
            start: 0.0,
            end: 1.0,
            totalSeconds: promptDelay,
            message: "[Dummy] 画像生成プロンプトの生成中",
            onProgress: onProgress
        )
        return PromptGenerationResult(
            imagePrompt: "[Dummy] Simulated prompt",
            selectedNewsIds: []
        )
    }

    func fetchOgpImages(
        context: PromptContext,
        selectedNewsIds _: [String]
    ) async -> PromptContext {
        // ダミー実装: OGP 取得なしで context をそのまま返す
        return context
    }

    func generateImageFromPrompt(
        imagePrompt: String,
        context: PromptContext,
        serviceTier _: GoogleAiServiceTier,
        onProgress: ((Double, String) -> Void)? = nil
    ) async throws -> GeneratedImageResult {
        let imageDelay = UInt64(configService.debugConfig.dummyImageDelaySeconds)
        try await simulateProgress(
            start: 0.0,
            end: 1.0,
            totalSeconds: imageDelay,
            message: "[Dummy] 壁紙画像の生成中",
            onProgress: onProgress
        )
        let fileURL = try await saveDummyImage(context: context)
        return GeneratedImageResult(
            filePath: fileURL.path,
            imagePrompt: imagePrompt
        )
    }

    // 指定時間かけて擬似進捗を通知する
    private func simulateProgress(
        start: Double,
        end: Double,
        totalSeconds: UInt64,
        message: String,
        onProgress: ((Double, String) -> Void)?
    ) async throws {
        let clampedStart = max(0.0, min(1.0, start))
        let clampedEnd = max(clampedStart, min(1.0, end))
        let duration = max(totalSeconds, 1)

        for second in 1...duration {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let ratio = Double(second) / Double(duration)
            let progress = clampedStart + (clampedEnd - clampedStart) * ratio
            onProgress?(progress, message)
        }
    }

    // ダミー壁紙を描画して保存する
    private func saveDummyImage(context: PromptContext) async throws -> URL {
        let canvasSize = dummyCanvasSize(
            imageSize: context.imageSize,
            aspectRatio: context.aspectRatio
        )

        let imageData = try await MainActor.run { () throws -> Data in
            guard let data = makeDummyWallpaperPngData(size: canvasSize, context: context) else {
                throw NSError(
                    domain: "WondayWall",
                    code: 500,
                    userInfo: [
                        NSLocalizedDescriptionKey: "ダミー画像データの生成に失敗しました。"
                    ]
                )
            }
            return data
        }

        let destination = FileHelper.getImageFilePath(extension: "png")
        try imageData.write(to: destination, options: .atomic)
        return destination
    }

    // PromptContext の imageSize / aspectRatio からキャンバスサイズを決める
    private func dummyCanvasSize(imageSize: String, aspectRatio: String) -> CGSize {
        let longEdge: CGFloat
        switch imageSize.uppercased() {
        case "4K": longEdge = 4096
        case "2K": longEdge = 2048
        case "1K": longEdge = 1024
        case "512": longEdge = 512
        default: longEdge = 1024
        }

        let ratio = parseAspectRatio(aspectRatio)
        if ratio <= 1.0 {
            return CGSize(width: max(256, longEdge * ratio), height: longEdge)
        }

        return CGSize(width: longEdge, height: max(256, longEdge / ratio))
    }

    // "9:16" 形式を width/height 比へ変換する
    private func parseAspectRatio(_ value: String) -> CGFloat {
        let parts = value.split(separator: ":")
        guard parts.count == 2,
            let w = Double(parts[0]),
            let h = Double(parts[1]),
            w > 0,
            h > 0
        else {
            return 9.0 / 16.0
        }
        return CGFloat(w / h)
    }

    // グラデーションと図形を描いたダミー壁紙 PNG を返す
    private func makeDummyWallpaperPngData(size: CGSize, context: PromptContext) -> Data? {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        // 毎回異なる見た目になるようにランダム値を生成する
        let colorThemes: [[(CGFloat, CGFloat, CGFloat)]] = [
            // 夜の海（デフォルト）
            [(0.06, 0.12, 0.30), (0.10, 0.28, 0.52), (0.96, 0.47, 0.24)],
            // 夕焼け
            [(0.60, 0.10, 0.20), (0.92, 0.40, 0.15), (0.98, 0.85, 0.30)],
            // 森
            [(0.05, 0.25, 0.10), (0.10, 0.50, 0.20), (0.80, 0.90, 0.30)],
            // 宇宙
            [(0.05, 0.00, 0.15), (0.20, 0.05, 0.40), (0.60, 0.10, 0.80)],
            // 朝焼け
            [(0.10, 0.15, 0.50), (0.70, 0.30, 0.50), (1.00, 0.75, 0.40)],
        ]
        let theme = colorThemes[Int.random(in: 0..<colorThemes.count)]

        // グラデーション方向のランダム化（斜め成分を加える）
        let startXOffset = CGFloat.random(in: -0.3...0.3)
        let endXOffset = CGFloat.random(in: -0.3...0.3)

        // 波形制御点のランダム化
        let waveStartY = CGFloat.random(in: 0.52...0.70)
        let waveEndY = CGFloat.random(in: 0.45...0.62)
        let cp1Y = CGFloat.random(in: 0.65...0.82)
        let cp2Y = CGFloat.random(in: 0.32...0.50)

        // 光の位置のランダム化
        let lightXOffset = CGFloat.random(in: -0.25...0.25)
        let lightYPos = CGFloat.random(in: 0.04...0.18)

        let image = renderer.image { renderContext in
            let cg = renderContext.cgContext
            let rect = CGRect(origin: .zero, size: size)

            let colors = [
                UIColor(red: theme[0].0, green: theme[0].1, blue: theme[0].2, alpha: 1).cgColor,
                UIColor(red: theme[1].0, green: theme[1].1, blue: theme[1].2, alpha: 1).cgColor,
                UIColor(red: theme[2].0, green: theme[2].1, blue: theme[2].2, alpha: 1).cgColor,
            ] as CFArray
            let locations: [CGFloat] = [0.0, 0.55, 1.0]
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: locations
            ) {
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: rect.midX + rect.width * startXOffset, y: 0),
                    end: CGPoint(x: rect.midX + rect.width * endXOffset, y: rect.maxY),
                    options: []
                )
            }

            // 上部の柔らかい光（位置をランダム化）
            cg.setFillColor(UIColor(white: 1.0, alpha: 0.18).cgColor)
            cg.fillEllipse(in: CGRect(
                x: rect.midX + rect.width * lightXOffset - rect.width * 0.38,
                y: rect.height * lightYPos,
                width: rect.width * 0.76,
                height: rect.width * 0.76
            ))

            // 波形のアクセント（制御点をランダム化）
            let wavePath = UIBezierPath()
            wavePath.move(to: CGPoint(x: 0, y: rect.height * waveStartY))
            wavePath.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.height * waveEndY),
                controlPoint1: CGPoint(x: rect.width * 0.25, y: rect.height * cp1Y),
                controlPoint2: CGPoint(x: rect.width * 0.74, y: rect.height * cp2Y)
            )
            wavePath.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            wavePath.addLine(to: CGPoint(x: 0, y: rect.maxY))
            wavePath.close()
            cg.setFillColor(UIColor(white: 1.0, alpha: 0.12).cgColor)
            cg.addPath(wavePath.cgPath)
            cg.fillPath()

            // ベース画像指定がある場合は白い枠を追加して視覚的に区別する
            if context.baseImagePath != nil {
                cg.setStrokeColor(UIColor(white: 1.0, alpha: 0.55).cgColor)
                cg.setLineWidth(max(2, rect.width * 0.008))
                let inset = rect.width * 0.06
                cg.stroke(
                    CGRect(
                        x: inset,
                        y: inset,
                        width: rect.width - inset * 2,
                        height: rect.height - inset * 2
                    )
                )
            }
        }

        return image.pngData()
    }
}
#endif
