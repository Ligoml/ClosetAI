import Foundation
import Security

// MARK: - Keychain Helper

enum KeychainKey {
    static let dashscopeAPIKey = "closetai.dashscope.apikey"
    static let ossAccessKeyID = "closetai.oss.accesskeyid"
    static let ossAccessKeySecret = "closetai.oss.accesskeysecret"
}

struct KeychainHelper {
    static func save(_ value: String, for key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(for key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    static func delete(for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - DashScope Response Models (OpenAI compatible format)

struct DashScopeResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

// MARK: - AliyunService

class AliyunService: ObservableObject {
    static let shared = AliyunService()

    private let dashscopeBaseURL = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"

    var dashscopeAPIKey: String {
        KeychainHelper.load(for: KeychainKey.dashscopeAPIKey) ?? ""
    }

    // MARK: - Auto Tagging with Qwen-VL-Plus

    func autoTagClothing(imageData: Data) async throws -> ClothingTags {
        let apiKey = dashscopeAPIKey
        guard !apiKey.isEmpty else {
            throw AliyunError.missingAPIKey
        }

        let base64Image = imageData.base64EncodedString()
        let imageURL = "data:image/jpeg;base64,\(base64Image)"

        let systemPrompt = """
        你是一个专业的服装分析师。请分析用户提供的服装图片，返回严格的 JSON 格式，不要添加任何额外说明。
        """

        let userPrompt = """
        请分析这件衣物，返回以下 JSON 格式（所有值为中文）：
        {
          "大类": "上装|下装|外套|连衣裙|鞋子|包包|配饰|其他",
          "小类": "具体品类，如T恤/牛仔裤/羽绒服等",
          "主色调": ["颜色1", "颜色2"],
          "图案": "纯色|条纹|格纹|花卉|几何|抽象|动物纹|其他",
          "风格": ["风格1", "风格2"],
          "季节": ["春|夏|秋|冬|四季"],
          "场合": ["日常|上班|约会|运动|正式|派对|旅行"],
          "备注": "简短描述"
        }
        """

        let requestBody: [String: Any] = [
            "model": "qwen-vl-plus",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": [
                    ["type": "image_url", "image_url": ["url": imageURL]],
                    ["type": "text", "text": userPrompt]
                ]]
            ],
            "max_tokens": 500
        ]

        guard let url = URL(string: dashscopeBaseURL) else {
            throw AliyunError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AliyunError.apiError("HTTP error: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }

        let dashResponse = try JSONDecoder().decode(DashScopeResponse.self, from: data)
        guard let content = dashResponse.choices.first?.message.content else {
            throw AliyunError.parseError
        }

        // Extract JSON from response
        let jsonString = extractJSON(from: content)
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw AliyunError.parseError
        }

        return try JSONDecoder().decode(ClothingTags.self, from: jsonData)
    }

    // MARK: - Wan2.6 Image Generation
    // Endpoint: POST .../multimodal-generation/generation
    // Docs: https://www.alibabacloud.com/help/en/model-studio/wan-image-generation-api-reference

    private func callWan26Image(images: [Data], prompt: String, size: String = "1024*1024") async throws -> Data {
        let apiKey = dashscopeAPIKey
        guard !apiKey.isEmpty else { throw AliyunError.missingAPIKey }

        // 图片放在前面，文字指令放最后——让模型先看图再读规则，提升图像内容遵从度
        var content: [[String: Any]] = []
        for imageData in images.prefix(4) {
            let base64 = imageData.base64EncodedString()
            content.append(["image": "data:image/jpeg;base64,\(base64)"])
        }
        content.append(["text": prompt])

        let requestBody: [String: Any] = [
            "model": "wan2.6-image",
            "input": [
                "messages": [
                    ["role": "user", "content": content]
                ]
            ],
            "parameters": [
                "size": size,
                "n": 1,
                "watermark": false,
                "prompt_extend": false
            ]
        ]

        guard let url = URL(string: "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation") else {
            throw AliyunError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 120 // 图像生成最长约 60-90 秒

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw AliyunError.apiError("生成失败 (\((response as? HTTPURLResponse)?.statusCode ?? -1)): \(body)")
        }

        // Response: output.choices[0].message.content[*].image (URL)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = json["output"] as? [String: Any],
              let choices = output["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let contentArray = message["content"] as? [[String: Any]] else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw AliyunError.apiError("解析响应失败: \(raw.prefix(300))")
        }

        guard let imageContent = contentArray.first(where: { $0["image"] != nil }),
              let imageURLString = imageContent["image"] as? String,
              let imageURL = URL(string: imageURLString) else {
            throw AliyunError.apiError("未找到生成的图片")
        }

        let (imgData, _) = try await URLSession.shared.data(from: imageURL)
        return imgData
    }

    // MARK: - AI Collage Generation (wan2.6)

    func generateAICollage(imageDatas: [Data], itemDescriptions: [String]) async throws -> Data {
        guard !imageDatas.isEmpty else { throw AliyunError.apiError("No images provided") }
        let n = imageDatas.count
        let itemList = itemDescriptions.enumerated()
            .map { "图\($0.offset + 1)=\($0.element)" }
            .joined(separator: "、")

        let prompt = """
        Arrange the \(n) clothing items shown above (\(itemList)) on a pure white background \
        to create a stylish flat lay outfit photo. \
        [MANDATORY LAYOUT RULES — violation = generation failure] \
        (1) The total number of garments in the image must be exactly \(n), no more, no less; \
        (2) Each garment must appear exactly once — no duplicates — strictly enforced; \
        (3) Do not add any garments or accessories not present in the input images; \
        (4) Preserve each item's original color, pattern, style, and length exactly — no modifications. \
        [Visual Style] \
        Pure white background, clean and minimal; \
        arrange items in real dressing order (outerwear over tops, tops over bottoms, shoes and accessories around) \
        to simulate how the outfit would look when worn; \
        pieces overlap naturally, each rotated 5–15° for dynamism; \
        soft diffused lighting with subtle shadows for depth and texture; \
        the overall composition should feel artistic and aspirational, \
        inspired by high-end fashion magazine flat lay editorials.
        """
        return try await callWan26Image(images: imageDatas, prompt: prompt, size: "1024*1024")
    }

    // MARK: - Collage Visual Enhancement (wan2.6)
    // 输入：Core Graphics 合成的准确平铺图；AI 只做视觉增强，不改变衣物数量和内容

    func enhanceCollage(baseCollageData: Data) async throws -> Data {
        let prompt = """
        这是一张已经合成好的服装 flat lay 穿搭图（Core Graphics 合成）。\
        请在完全保留画面中所有衣物的原始数量、位置和内容不变的前提下，\
        优化整体视觉质感：光影更立体自然、衣物褶皱纹理更真实、背景更纯白干净，\
        整体达到时尚杂志 flat lay 级别的视觉效果。\
        严禁添加、删除、替换或移动任何衣物。
        """
        return try await callWan26Image(images: [baseCollageData], prompt: prompt, size: "1024*1024")
    }

    // MARK: - Virtual Try-On (wan2.6)

    func virtualTryOn(personImageData: Data, clothingItems: [Data]) async throws -> Data {
        let allImages = [personImageData] + Array(clothingItems.prefix(3))
        let prompt = """
        你是一个 AI 试衣专家。第一张图是模特，后续图片是需要穿上的服装。\
        请给模特穿上这些服装，同时保持人物姿态和衣服特征细节不变。\
        要求：人物面部、发型、姿势完整保留；服装贴合身形，保持原有颜色、图案、款式、长度不变；\
        光影自然过渡；输出完整全身试穿效果图。
        """
        return try await callWan26Image(images: Array(allImages), prompt: prompt, size: "768*1280")
    }

    // MARK: - Private Helpers

    private func extractJSON(from text: String) -> String {
        // Try to find JSON block in markdown code block
        if let range = text.range(of: "```json\n"),
           let endRange = text.range(of: "\n```", range: range.upperBound..<text.endIndex) {
            return String(text[range.upperBound..<endRange.lowerBound])
        }
        // Try to find raw JSON
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }
        return text
    }

    private func extractImageURL(from text: String) -> String? {
        let pattern = "https?://[^\\s]+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        if let match = regex.firstMatch(in: text, range: range),
           let urlRange = Range(match.range, in: text) {
            return String(text[urlRange])
        }
        return nil
    }

    private func extractBase64(from text: String) -> String? {
        // Look for base64 encoded image data
        let pattern = "data:image/[^;]+;base64,([A-Za-z0-9+/=]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        if let match = regex.firstMatch(in: text, range: range),
           match.numberOfRanges > 1,
           let dataRange = Range(match.range(at: 1), in: text) {
            return String(text[dataRange])
        }
        return nil
    }
}

// MARK: - Errors

enum AliyunError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case apiError(String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "请在设置中配置 DashScope API Key"
        case .invalidURL: return "无效的 API 地址"
        case .apiError(let msg): return "API 错误: \(msg)"
        case .parseError: return "解析响应失败"
        }
    }
}
