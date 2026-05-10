import Foundation
import UIKit

// 実 API を使わずに遅延付きで動作を再現するダミー実装
final class DummyGoogleAiService: GoogleAiServiceProtocol {
    private static let promptDelaySeconds: UInt64 = 180
    private static let imageDelaySeconds: UInt64 = 600

    func generateWallpaper(
        context: PromptContext,
        serviceTier _: GoogleAiServiceTier,
        onProgress: ((Double, String) -> Void)? = nil
    ) async throws -> GeneratedImageResult {
        onProgress?(0.35, "[Dummy] 画像生成プロンプトの生成中")
        try await simulateProgress(
            start: 0.35,
            end: 0.65,
            totalSeconds: Self.promptDelaySeconds,
            message: "[Dummy] 画像生成プロンプトの生成中",
            onProgress: onProgress
        )

        onProgress?(0.65, "[Dummy] 壁紙画像の生成中")
        try await simulateProgress(
            start: 0.65,
            end: 0.95,
            totalSeconds: Self.imageDelaySeconds,
            message: "[Dummy] 壁紙画像の生成中",
            onProgress: onProgress
        )

        let fileURL = try await saveDummyImage(context: context)
        onProgress?(1.0, "[Dummy] 画像生成完了")

        return GeneratedImageResult(
            filePath: fileURL.path,
            imagePrompt: "[Dummy] Simulated prompt after 3 minutes",
            selectedNewsIds: []
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

        let image = renderer.image { renderContext in
            let cg = renderContext.cgContext
            let rect = CGRect(origin: .zero, size: size)

            let colors = [
                UIColor(red: 0.06, green: 0.12, blue: 0.30, alpha: 1).cgColor,
                UIColor(red: 0.10, green: 0.28, blue: 0.52, alpha: 1).cgColor,
                UIColor(red: 0.96, green: 0.47, blue: 0.24, alpha: 1).cgColor,
            ] as CFArray
            let locations: [CGFloat] = [0.0, 0.55, 1.0]
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: locations
            ) {
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: rect.midX, y: 0),
                    end: CGPoint(x: rect.midX, y: rect.maxY),
                    options: []
                )
            }

            // 上部の柔らかい光
            cg.setFillColor(UIColor(white: 1.0, alpha: 0.18).cgColor)
            cg.fillEllipse(in: CGRect(
                x: rect.midX - rect.width * 0.38,
                y: rect.height * 0.08,
                width: rect.width * 0.76,
                height: rect.width * 0.76
            ))

            // 波形のアクセント
            let wavePath = UIBezierPath()
            wavePath.move(to: CGPoint(x: 0, y: rect.height * 0.62))
            wavePath.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.height * 0.52),
                controlPoint1: CGPoint(x: rect.width * 0.25, y: rect.height * 0.74),
                controlPoint2: CGPoint(x: rect.width * 0.74, y: rect.height * 0.40)
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
