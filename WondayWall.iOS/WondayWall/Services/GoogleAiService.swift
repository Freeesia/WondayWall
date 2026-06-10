import CryptoKit
import Foundation
import OSLog

// 壁紙生成サービスの抽象インターフェイス
protocol AiService: AnyObject {
    // テキストモデルで画像生成プロンプトを生成する（ステップ 1）
    func generatePrompt(
        context: PromptContext,
        serviceTier: GoogleAiServiceTier,
        onProgress: ((Double, String) -> Void)?
    ) async throws -> PromptGenerationResult

    // 採用ニュースの OGP 画像をダウンロードして context に付加する（ステップ 1.5）
    // 失敗は無視し、ダウンロードできた分だけ反映した context を返す
    func fetchOgpImages(
        context: PromptContext,
        selectedNewsIds: [String]
    ) async -> PromptContext

    // 画像プロンプトから壁紙を生成してローカルに保存する（ステップ 2）
    // context.newsTopics の ogpImageData が非 nil のものをリファレンス画像として使用する
    func generateImageFromPrompt(
        imagePrompt: String,
        context: PromptContext,
        serviceTier: GoogleAiServiceTier,
        onProgress: ((Double, String) -> Void)?
    ) async throws -> GeneratedImageResult
}

// Google AI Gemini API を使った画像生成サービス
final class GoogleAiService: AiService {
    private static let textModelName = "gemini-3-flash-preview"
    private static let imageModelName = "gemini-3.1-flash-image-preview"
    private static let apiBaseURL =
        "https://generativelanguage.googleapis.com/v1beta/models"

    // タイムアウト秒数（Flex はキューに積まれることがあるため 660 秒以上推奨）
    private static let googleApiTimeout: TimeInterval = 660

    private let logger = Logger(subsystem: "com.studiofreesia.wondaywall", category: "GoogleAiService")
    private let configService: AppConfigService

    init(configService: AppConfigService) {
        self.configService = configService
    }

    // API キーを取得する（未設定の場合はエラーを投げる）
    private func requireApiKey() throws -> String {
        let key = configService.googleAiApiKey
        guard !key.isEmpty else {
            throw NSError(
                domain: "WondayWall", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Google AI API キーが設定されていません。"]
            )
        }
        return key
    }

    // テキストモデルで詳細な画像プロンプトを生成する（ステップ 1）
    // Flex 失敗時は Standard にフォールバック
    func generatePrompt(
        context: PromptContext,
        serviceTier: GoogleAiServiceTier = .standard,
        onProgress: ((Double, String) -> Void)? = nil
    ) async throws -> PromptGenerationResult {
        let apiKey = try requireApiKey()
        let promptSelection = try await runWithSyntheticProgress(
            start: 0.0,
            end: 1.0,
            onProgress: { onProgress?($0, "画像生成プロンプトの生成中") }
        ) {
            try await self.generatePromptSelectionWithFallback(
                context: context, apiKey: apiKey, serviceTier: serviceTier
            )
        }
        return PromptGenerationResult(
            imagePrompt: promptSelection.imagePrompt,
            selectedNewsIds: promptSelection.selectedNewsIds
        )
    }

    // 採用ニュースの OGP 画像をダウンロードして context に付加する（ステップ 1.5）
    // キャッシュ（Caches/WondayWall/ogp/）があればダウンロードをスキップする
    // ダウンロード失敗は無視し、成功分だけ ogpImageData / ogpImageMimeType を設定して返す
    func fetchOgpImages(
        context: PromptContext,
        selectedNewsIds: [String]
    ) async -> PromptContext {
        let selectedIds = Set(selectedNewsIds)
        var newsTopics = context.newsTopics

        // 採用ニュースのインデックスを最大3件抽出する
        let targets = Array(
            newsTopics.enumerated()
                .filter { selectedIds.contains($0.element.id) }
                .prefix(3)
        )

        // 並列でキャッシュ確認 or ダウンロードし (index, data, mimeType) を収集する
        let downloads = await withTaskGroup(
            of: (Int, Data, String)?.self,
            returning: [(Int, Data, String)].self
        ) { group in
            for (idx, topic) in targets {
                guard let urlString = topic.ogpImageUrl,
                    let imgUrl = URL(string: urlString)
                else { continue }
                group.addTask {
                    // キャッシュがあれば即返す
                    if let (cachedData, cachedMime) = Self.loadOgpFromCache(for: imgUrl) {
                        return (idx, cachedData, cachedMime)
                    }
                    // キャッシュがなければダウンロードしてキャッシュに保存する
                    do {
                        var request = URLRequest(url: imgUrl, timeoutInterval: 10)
                        request.setValue(
                            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)",
                            forHTTPHeaderField: "User-Agent"
                        )
                        let (data, response) = try await URLSession.shared.data(for: request)
                        let mimeType = response.mimeType ?? "image/jpeg"
                        Self.saveOgpToCache(data: data, mimeType: mimeType, for: imgUrl)
                        return (idx, data, mimeType)
                    } catch {
                        // OGP 画像のダウンロード失敗は無視する
                        return nil
                    }
                }
            }
            var collected: [(Int, Data, String)] = []
            for await item in group {
                if let item { collected.append(item) }
            }
            return collected
        }

        for (idx, data, mimeType) in downloads {
            newsTopics[idx].ogpImageData = data
            newsTopics[idx].ogpImageMimeType = mimeType
        }

        var updatedContext = context
        updatedContext.newsTopics = newsTopics
        return updatedContext
    }

    // MARK: - OGP 画像キャッシュ

    // キャッシュの保存先ディレクトリ
    private static var ogpCacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WondayWall/ogp", isDirectory: true)
    }

    // URL の SHA256 ハッシュをファイル名としたキャッシュファイル URL を返す
    private static func ogpCacheFileURL(for imageUrl: URL) -> URL {
        let hash = SHA256.hash(data: Data(imageUrl.absoluteString.utf8))
        let filename = hash.compactMap { String(format: "%02x", $0) }.joined()
        return ogpCacheDirectory.appendingPathComponent(filename)
    }

    // OGP 画像をキャッシュから読み込む（キャッシュなしは nil）
    private static func loadOgpFromCache(for imageUrl: URL) -> (Data, String)? {
        let fileURL = ogpCacheFileURL(for: imageUrl)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let mimeType =
            (try? String(contentsOf: fileURL.appendingPathExtension("mime"), encoding: .utf8))
            ?? "image/jpeg"
        return (data, mimeType)
    }

    // OGP 画像をキャッシュに保存する（失敗は無視する）
    private static func saveOgpToCache(data: Data, mimeType: String, for imageUrl: URL) {
        let fileURL = ogpCacheFileURL(for: imageUrl)
        try? FileManager.default.createDirectory(
            at: ogpCacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
        try? mimeType.write(
            to: fileURL.appendingPathExtension("mime"), atomically: true, encoding: .utf8)
    }

    // 画像プロンプトから壁紙を生成してローカルに保存する（ステップ 2）
    // context.newsTopics の ogpImageData が非 nil のものをリファレンス画像として使用する
    // Flex 失敗時は Standard にフォールバック
    func generateImageFromPrompt(
        imagePrompt: String,
        context: PromptContext,
        serviceTier: GoogleAiServiceTier = .standard,
        onProgress: ((Double, String) -> Void)? = nil
    ) async throws -> GeneratedImageResult {
        let apiKey = try requireApiKey()
        let imageData = try await runWithSyntheticProgress(
            start: 0.0,
            end: 1.0,
            onProgress: { onProgress?($0, "壁紙画像の生成中") }
        ) {
            try await self.generateImageWithFallback(
                prompt: imagePrompt,
                context: context,
                apiKey: apiKey,
                serviceTier: serviceTier
            )
        }
        let filePath = FileHelper.getImageFilePath(extension: imageData.extension)
        try imageData.bytes.write(to: filePath, options: .atomic)
        return GeneratedImageResult(
            filePath: filePath.path,
            imagePrompt: imagePrompt
        )
    }

    // Flex → Standard フォールバック付きでプロンプトを生成する
    private func generatePromptSelectionWithFallback(
        context: PromptContext,
        apiKey: String,
        serviceTier: GoogleAiServiceTier
    ) async throws -> PromptSelectionResponse {
        if serviceTier != .flex {
            return try await generatePromptSelection(context: context, apiKey: apiKey, serviceTier: .standard)
        }
        do {
            return try await generatePromptSelection(context: context, apiKey: apiKey, serviceTier: .flex)
        } catch let error as NSError where isFlexUnavailableError(error) {
            // Flex 容量不足（503/429）→ Standard で再試行
            return try await generatePromptSelection(context: context, apiKey: apiKey, serviceTier: .standard)
        }
    }

    // テキストモデルで画像プロンプト候補を生成する
    private func generatePromptSelection(
        context: PromptContext,
        apiKey: String,
        serviceTier: GoogleAiServiceTier = .standard
    ) async throws -> PromptSelectionResponse {
        let endpoint = "\(Self.apiBaseURL)/\(Self.textModelName):generateContent?key=\(apiKey)"
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }

        let systemPrompt = buildTextModelPrompt(context: context)
        let requestBody = GeminiRequest(
            contents: [
                GeminiContent(
                    role: "user",
                    parts: [GeminiPart(text: systemPrompt)]
                )
            ],
            generationConfig: GeminiGenerationConfig(
                responseMimeType: "application/json",
                responseSchema: PromptSelectionSchema.schema
            ),
            tools: [GeminiTool(googleSearch: GeminiGoogleSearch())],
            serviceTier: serviceTier == .flex ? "flex" : nil
        )

        let responseData = try await postJSON(url: url, body: requestBody)
        let response = try JSONDecoder().decode(GeminiResponse.self, from: responseData)

        guard let text = response.candidates.first?.content.parts.first?.text,
            let jsonData = text.data(using: .utf8)
        else {
            throw NSError(
                domain: "WondayWall", code: 500,
                userInfo: [
                    NSLocalizedDescriptionKey: "Google AI から有効なプロンプト選択レスポンスを取得できませんでした。"
                ]
            )
        }

        let selection = try JSONDecoder().decode(PromptSelectionResponse.self, from: jsonData)
        guard !selection.imagePrompt.isEmpty else {
            throw NSError(
                domain: "WondayWall", code: 500,
                userInfo: [
                    NSLocalizedDescriptionKey: "Google AI が有効な画像プロンプトを返しませんでした。"
                ]
            )
        }
        return selection
    }

    // Flex → Standard フォールバック付きで画像を生成する
    private func generateImageWithFallback(
        prompt: String,
        context: PromptContext,
        apiKey: String,
        serviceTier: GoogleAiServiceTier
    ) async throws -> (bytes: Data, `extension`: String) {
        if serviceTier != .flex {
            return try await generateImage(
                prompt: prompt, context: context,
                apiKey: apiKey, serviceTier: .standard)
        }
        do {
            return try await generateImage(
                prompt: prompt, context: context,
                apiKey: apiKey, serviceTier: .flex)
        } catch let error as NSError where isFlexUnavailableError(error) {
            // Flex 容量不足（503/429）→ Standard で再試行
            return try await generateImage(
                prompt: prompt, context: context,
                apiKey: apiKey, serviceTier: .standard)
        }
    }

    // 画像モデルで壁紙画像を生成する
    private func generateImage(
        prompt: String,
        context: PromptContext,
        apiKey: String,
        serviceTier: GoogleAiServiceTier = .standard
    ) async throws -> (bytes: Data, `extension`: String) {
        let endpoint = "\(Self.apiBaseURL)/\(Self.imageModelName):generateContent?key=\(apiKey)"
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }

        // OGP 画像データを持つニューストピックを収集する（最大3件）
        let ogpTopics = context.newsTopics
            .filter { $0.ogpImageData != nil }
            .prefix(3)

        let imagePrompt = ogpTopics.isEmpty ? prompt : """
            \(prompt)

            Reference images from the selected news topics are attached. Incorporate their visual themes, color palette, and subject matter into the wallpaper design.
            """

        var parts: [GeminiPart] = []

        // ベース壁紙がある場合は先頭に付加する
        if let basePath = context.baseImagePath,
            let baseData = try? Data(contentsOf: URL(fileURLWithPath: basePath))
        {
            let mimeType = mimeType(forPath: basePath)
            parts.append(
                GeminiPart(
                    inlineData: GeminiInlineData(
                        mimeType: mimeType,
                        data: baseData.base64EncodedString()
                    )
                )
            )
            let finalPrompt =
                """
                The current wallpaper is provided as the base image.
                Create a new wallpaper that evolves gradually from this base.
                Visually inspect the base wallpaper and compare it against the current prompt.
                Treat the current prompt's events, news themes, and mood as the source of truth.
                Remove or replace any subject, motif, decoration, or symbolic element from the base image that no longer matches the current prompt.
                When the base image conflicts with the current prompt, prioritize the current prompt while preserving the base image's overall composition, color palette, and artistic style.
                Preserve the overall composition, color palette, and artistic style of the base wallpaper. Incorporate the new themes and events subtly — avoid drastic visual changes.

                \(imagePrompt)
                """
            parts.append(GeminiPart(text: finalPrompt))
        } else {
            parts.append(GeminiPart(text: imagePrompt))
        }

        // ダウンロード済み OGP 画像をインラインデータとして添付する
        for topic in ogpTopics {
            guard let data = topic.ogpImageData else { continue }
            let mimeType = topic.ogpImageMimeType ?? "image/jpeg"
            parts.append(GeminiPart(inlineData: GeminiInlineData(
                mimeType: mimeType,
                data: data.base64EncodedString()
            )))
        }

        let requestBody = GeminiRequest(
            contents: [GeminiContent(role: "user", parts: parts)],
            generationConfig: GeminiGenerationConfig(
                responseModalities: ["IMAGE"],
                imageConfig: GeminiImageConfig(
                    aspectRatio: context.aspectRatio,
                    imageSize: context.imageSize
                )
            ),
            tools: [GeminiTool(googleSearch: GeminiGoogleSearch())],
            serviceTier: serviceTier == .flex ? "flex" : nil
        )

        let responseData = try await postJSON(url: url, body: requestBody)
        let response = try JSONDecoder().decode(GeminiResponse.self, from: responseData)

        for candidate in response.candidates {
            for part in candidate.content.parts {
                if let inlineData = part.inlineData,
                    inlineData.mimeType.hasPrefix("image/"),
                    let data = Data(base64Encoded: inlineData.data)
                {
                    let ext = String(inlineData.mimeType.dropFirst("image/".count))
                    return (data, ext.isEmpty ? "jpg" : ext)
                }
            }
        }

        throw NSError(
            domain: "WondayWall", code: 500,
            userInfo: [
                NSLocalizedDescriptionKey: "Google AI から画像データを取得できませんでした。"
            ]
        )
    }

    // テキストモデルに送るプロンプトを構築する
    private func buildTextModelPrompt(context: PromptContext) -> String {
        var parts: [String] = []

        parts.append(
            """
            You are an expert mobile wallpaper image-generation prompt writer.
            You will be given calendar events, news topics, and optionally reference images from those news articles.
            You MUST aggressively use Google Search before writing the prompt.
            Research broadly and actively: run multiple targeted searches per topic (official sources, recent coverage,
            image references, and related background context), then cross-check recency and consistency.
            Prefer fresh, high-signal information and concrete visual details you can translate into imagery.
            Do not rely only on the user's short summaries when searchable context exists.
            Your task: review all candidate calendar events and news topics, decide which ones should materially influence
            the wallpaper, and then write a single detailed, creative English prompt for an image generation model
            (\(context.imageSize) resolution, \(context.aspectRatio) aspect ratio) that creates a beautiful iPhone wallpaper.

            The wallpaper should visually reflect the themes, mood, and atmosphere of the selected events and news.
            If reference images are supplied later, they will correspond only to selected news topics.
            Describe visual elements, style, mood, color palette, lighting, and composition in detail.
            No text, logos, or UI overlays. Portrait orientation.

            For calendar events:
            - Only include POSITIVE events (celebrations, trips, parties, hobbies, achievements, social gatherings, etc.)
              in the visual design. Ignore NEGATIVE or NEUTRAL events (medical appointments, work deadlines,
              chores, administrative tasks, etc.), but do not let them suppress other event or news candidates.
            - Each event has a proximity tag indicating when it occurs. Use it to determine the visual weight:
              [today] or [tomorrow]: this event DOMINATES the entire image — make it the primary subject and theme,
                occupying nearly all visual elements.
              [in 2-3 days]: this event is a MAJOR visual theme, occupying 50–70% of the image's visual elements.
              [in 4-7 days]: this event is a MINOR accent or background element (15–30% of visual elements).
            - When multiple positive events are present, prioritize the ones happening sooner.
            - If the nearest event is NEGATIVE or NEUTRAL, ignore it and continue considering later positive events
              and news topics as potential primary themes.

            Return a response that matches the configured JSON schema.
            - imagePrompt must be a single detailed English prompt for the image model.
            - selectedNewsIds must contain only ids of news topics that materially influenced imagePrompt.
            - If no news topic is used, selectedNewsIds must be an empty array.
            - Do not output markdown fences or any extra explanation.
            """
        )

        if let basePath = context.baseImagePath, FileManager.default.fileExists(atPath: basePath) {
            parts.append(
                """
                A base wallpaper image will be supplied to the image model.
                Preserve the overall composition, color palette, and artistic style of the base wallpaper.
                Incorporate the new themes and events subtly — avoid drastic visual changes.
                """
            )
        }

        if !context.calendarEvents.isEmpty {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let json = try? encoder.encode(context.calendarEvents),
                let jsonString = String(data: json, encoding: .utf8)
            {
                parts.append(
                    """
                    Calendar event candidates (JSON):
                    \(jsonString)
                    """
                )
            }
        }

        if !context.newsTopics.isEmpty {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let json = try? encoder.encode(context.newsTopics),
                let jsonString = String(data: json, encoding: .utf8)
            {
                parts.append(
                    """
                    News topic candidates (JSON):
                    \(jsonString)
                    """
                )
            }
        }

        if !context.additionalConstraints.isEmpty {
            parts.append("Additional instructions: \(context.additionalConstraints)")
        }

        return parts.joined(separator: "\n\n")
    }

    // JSON エンコードして POST し、レスポンスデータを返す
    private func postJSON<T: Encodable>(
        url: URL,
        body: T
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = Self.googleApiTimeout

        let endpointPath = url.path
        logger.notice("postJSON 開始: endpoint=\(endpointPath, privacy: .public) timeout=\(Int(Self.googleApiTimeout), privacy: .public)s")
        let startTime = Date()

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            let elapsed = Date().timeIntervalSince(startTime)
            logger.error("postJSON 失敗: endpoint=\(endpointPath, privacy: .public) elapsed=\(String(format: "%.1f", elapsed), privacy: .public)s error=\(error.localizedDescription, privacy: .public)")
            throw error
        }

        let elapsed = Date().timeIntervalSince(startTime)
        if let httpResponse = response as? HTTPURLResponse {
            logger.notice("postJSON 完了: endpoint=\(endpointPath, privacy: .public) status=\(httpResponse.statusCode, privacy: .public) elapsed=\(String(format: "%.1f", elapsed), privacy: .public)s")
            if !(200..<300).contains(httpResponse.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? "(empty)"
                throw NSError(
                    domain: "WondayWall",
                    code: httpResponse.statusCode,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Google AI APIエラー (\(httpResponse.statusCode)): \(body)"
                    ]
                )
            }
        }
        return data
    }

    // Flex 容量不足を示すエラーか判定する（503 / 429）
    private func isFlexUnavailableError(_ error: NSError) -> Bool {
        error.code == 503 || error.code == 429
    }

    // ファイルパスから MIME タイプを返す
    private func mimeType(forPath path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "webp": return "image/webp"
        default: return "image/jpeg"
        }
    }

    // 長時間待機の間に擬似進捗を更新して、BGContinuedProcessingTask が無進捗で終了されるのを防ぐ
    private func runWithSyntheticProgress<T>(
        start: Double,
        end: Double,
        intervalNanoseconds: UInt64 = 1_000_000_000,
        onProgress: @escaping (Double) -> Void,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        let clampedStart = max(0.0, min(1.0, start))
        let clampedEnd = max(clampedStart, min(1.0, end))
        onProgress(clampedStart)

        let step = max((clampedEnd - clampedStart) / 20.0, 0.01)
        let ticker = Task {
            var current = clampedStart
            while !Task.isCancelled && current < clampedEnd {
                try? await Task.sleep(nanoseconds: intervalNanoseconds)
                current = min(clampedEnd, current + step)
                onProgress(current)
            }
        }

        defer {
            ticker.cancel()
        }

        let result = try await operation()
        onProgress(clampedEnd)
        return result
    }

    // MARK: - Gemini API リクエスト/レスポンスモデル

    private struct GeminiRequest: Encodable {
        let contents: [GeminiContent]
        var generationConfig: GeminiGenerationConfig?
        var tools: [GeminiTool]?
        // Flex 推論時は "flex"、通常は nil（省略すると Standard）
        var serviceTier: String?

        enum CodingKeys: String, CodingKey {
            case contents, generationConfig, tools
            case serviceTier = "service_tier"
        }
    }

    private struct GeminiContent: Encodable {
        let role: String
        let parts: [GeminiPart]
    }

    private struct GeminiPart: Encodable {
        var text: String?
        var inlineData: GeminiInlineData?
    }

    private struct GeminiInlineData: Encodable {
        let mimeType: String
        let data: String
    }

    private struct GeminiGenerationConfig: Encodable {
        var responseMimeType: String?
        var responseSchema: [String: JSONValue]?
        var responseModalities: [String]?
        var imageConfig: GeminiImageConfig?
    }

    private struct GeminiImageConfig: Encodable {
        let aspectRatio: String
        let imageSize: String
    }

    private struct GeminiTool: Encodable {
        var googleSearch: GeminiGoogleSearch?
    }

    private struct GeminiGoogleSearch: Encodable {}

    private struct GeminiResponse: Decodable {
        let candidates: [GeminiCandidate]
    }

    private struct GeminiCandidate: Decodable {
        let content: GeminiResponseContent
    }

    private struct GeminiResponseContent: Decodable {
        let parts: [GeminiResponsePart]
    }

    private struct GeminiResponsePart: Decodable {
        var text: String?
        var inlineData: GeminiResponseInlineData?
    }

    private struct GeminiResponseInlineData: Decodable {
        let mimeType: String
        let data: String
    }

    private struct PromptSelectionResponse: Decodable {
        let imagePrompt: String
        let selectedNewsIds: [String]
    }

    // Gemini API の JSON スキーマ定義
    private enum PromptSelectionSchema {
        static let schema: [String: JSONValue] = [
            "type": "object",
            "properties": [
                "imagePrompt": ["type": "string"],
                "selectedNewsIds": [
                    "type": "array",
                    "items": ["type": "string"],
                ],
            ],
            "required": ["imagePrompt", "selectedNewsIds"],
        ]
    }
}

// テキストモデルのプロンプト生成結果（ステップ 1 の戻り値）
struct PromptGenerationResult {
    let imagePrompt: String
    let selectedNewsIds: [String]
    let usedNewsTopics: [NewsTopicItem]?

    init(
        imagePrompt: String,
        selectedNewsIds: [String],
        usedNewsTopics: [NewsTopicItem]? = nil
    ) {
        self.imagePrompt = imagePrompt
        self.selectedNewsIds = selectedNewsIds
        self.usedNewsTopics = usedNewsTopics
    }
}

// 画像生成結果（ステップ 2 の戻り値）
struct GeneratedImageResult {
    let filePath: String
    let imagePrompt: String
}

// Gemini API スキーマ定義用の汎用 JSON 値型
indirect enum JSONValue: Encodable {
    case string(String)
    case object([String: JSONValue])
    case array([JSONValue])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .object(let d): try container.encode(d)
        case .array(let a): try container.encode(a)
        }
    }
}

// Dictionary リテラルと Array リテラルで JSONValue を使えるようにする
extension JSONValue: ExpressibleByStringLiteral {
    init(stringLiteral value: String) { self = .string(value) }
}
extension JSONValue: ExpressibleByDictionaryLiteral {
    init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}
extension JSONValue: ExpressibleByArrayLiteral {
    init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}
