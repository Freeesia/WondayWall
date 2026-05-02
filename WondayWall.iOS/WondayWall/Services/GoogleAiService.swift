import Foundation

// Google AI Gemini API を使った画像生成サービス
final class GoogleAiService {
    private static let textModelName = "gemini-2.5-flash-preview-04-17"
    private static let imageModelName = "gemini-2.0-flash-preview-image-generation"
    private static let apiBaseURL =
        "https://generativelanguage.googleapis.com/v1beta/models"

    private let configService: AppConfigService

    init(configService: AppConfigService) {
        self.configService = configService
    }

    // 壁紙画像を生成してローカルに保存し、ファイルパスを返す
    func generateWallpaper(context: PromptContext) async throws -> GeneratedImageResult {
        let apiKey = configService.config.googleAiApiKey
        guard !apiKey.isEmpty else {
            throw NSError(
                domain: "WondayWall", code: 400,
                userInfo: [
                    NSLocalizedDescriptionKey: "Google AI API キーが設定されていません。"
                ]
            )
        }

        // ステップ1: テキストモデルで詳細な画像プロンプトを生成
        let promptSelection = try await generatePromptSelection(context: context, apiKey: apiKey)

        // ステップ2: 画像モデルで壁紙を生成
        let imageData = try await generateImage(
            prompt: promptSelection.imagePrompt,
            context: context,
            selectedNewsIds: Set(promptSelection.selectedNewsIds),
            apiKey: apiKey
        )

        // 画像をローカルに保存
        let filePath = FileHelper.getImageFilePath(extension: imageData.extension)
        try imageData.bytes.write(to: filePath, options: .atomic)

        return GeneratedImageResult(
            filePath: filePath.path,
            imagePrompt: promptSelection.imagePrompt,
            selectedNewsIds: promptSelection.selectedNewsIds
        )
    }

    // テキストモデルで画像プロンプト候補を生成する
    private func generatePromptSelection(
        context: PromptContext,
        apiKey: String
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
            tools: [GeminiTool(googleSearch: GeminiGoogleSearch())]
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

    // 画像モデルで壁紙画像を生成する
    private func generateImage(
        prompt: String,
        context: PromptContext,
        selectedNewsIds: Set<String>,
        apiKey: String
    ) async throws -> (bytes: Data, `extension`: String) {
        let endpoint = "\(Self.apiBaseURL)/\(Self.imageModelName):generateContent?key=\(apiKey)"
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }

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
                Preserve the overall composition, color palette, and artistic style.
                Incorporate the new themes and events subtly — avoid drastic visual changes.

                \(prompt)
                """
            parts.append(GeminiPart(text: finalPrompt))
        } else {
            parts.append(GeminiPart(text: prompt))
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
            tools: [GeminiTool(googleSearch: GeminiGoogleSearch())]
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
            Describe visual elements, style, mood, color palette, lighting, and composition in detail.
            No text, logos, or UI overlays. Portrait orientation.

            For calendar events:
            - Only include POSITIVE events (celebrations, trips, parties, hobbies, achievements, social gatherings, etc.)
              in the visual design. Ignore NEGATIVE or NEUTRAL events (medical appointments, work deadlines,
              chores, administrative tasks, etc.).
            - Each event has a proximity tag indicating when it occurs. Use it to determine the visual weight:
              [today] or [tomorrow]: this event DOMINATES the entire image.
              [in 2-3 days]: this event is a MAJOR visual theme.
              [in 4-7 days]: this event is a MINOR accent or background element.
            - When multiple positive events are present, prioritize the ones happening sooner.

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
    private func postJSON<T: Encodable>(url: URL, body: T) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        // 画像生成は時間がかかることがあるためタイムアウトを延長
        request.timeoutInterval = 300
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
            !(200..<300).contains(httpResponse.statusCode)
        {
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
        return data
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

    // MARK: - Gemini API リクエスト/レスポンスモデル

    private struct GeminiRequest: Encodable {
        let contents: [GeminiContent]
        var generationConfig: GeminiGenerationConfig?
        var tools: [GeminiTool]?
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

// 画像生成結果
struct GeneratedImageResult {
    let filePath: String
    let imagePrompt: String
    let selectedNewsIds: [String]
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
