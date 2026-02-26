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

    // MARK: - AI Collage Generation with qwen-image-edit-max

    /// Generate an outfit collage using qwen-image-edit-max (sync).
    /// Endpoint: multimodal-generation/generation
    /// Response: output.choices[0].message.content[0].image (URL string)
    func generateAICollage(imageDatas: [Data], itemDescriptions: [String]) async throws -> Data {
        let apiKey = dashscopeAPIKey
        guard !apiKey.isEmpty else { throw AliyunError.missingAPIKey }
        guard !imageDatas.isEmpty else { throw AliyunError.apiError("No images provided") }

        // Build content: one {"image": "data:..."} per clothing item, then text prompt
        var content: [[String: Any]] = []
        for imgData in imageDatas {
            let base64 = imgData.base64EncodedString()
            content.append(["image": "data:image/jpeg;base64,\(base64)"])
        }
        let itemDesc = itemDescriptions.isEmpty
            ? "这些服装单品"
            : itemDescriptions.joined(separator: "、")
        content.append(["text": "请用以上\(imageDatas.count)件服装（\(itemDesc)）生成一张穿搭平铺展示图。要求：白色干净背景；按照人体穿着逻辑将衣物叠放组合，上装在上、下装在下、外套覆盖在上装外面、鞋子置于最下方；衣物之间自然重叠，模拟实际上身穿搭的视觉效果；整体平铺俯视视角，构图像时尚杂志的穿搭 flat lay 风格。"])

        let requestBody: [String: Any] = [
            "model": "qwen-image-edit-max",
            "input": [
                "messages": [
                    ["role": "user", "content": content]
                ]
            ],
            "parameters": [
                "size": "1024*1024",
                "watermark": false
            ]
        ]

        guard let url = URL(string: "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation") else {
            throw AliyunError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120  // sync call, allow up to 2 min
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw AliyunError.apiError("Collage API error (\((response as? HTTPURLResponse)?.statusCode ?? -1)): \(body)")
        }

        // Parse: output.choices[0].message.content[0].image
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = json["output"] as? [String: Any],
              let choices = output["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let contentArr = message["content"] as? [[String: Any]],
              let firstItem = contentArr.first,
              let imageURLStr = firstItem["image"] as? String,
              let imageURL = URL(string: imageURLStr) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw AliyunError.apiError("Failed to parse collage response: \(body)")
        }

        let (imgData, _) = try await URLSession.shared.data(from: imageURL)
        return imgData
    }

    // MARK: - Virtual Try-On with qwen-vl-plus (image editing)

    func virtualTryOn(personImageData: Data, clothingItems: [Data]) async throws -> Data {
        let apiKey = dashscopeAPIKey
        guard !apiKey.isEmpty else {
            throw AliyunError.missingAPIKey
        }

        let personBase64 = personImageData.base64EncodedString()
        var content: [[String: Any]] = [
            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(personBase64)"]],
            ["type": "text", "text": "这是需要试穿服装的人物图片。"]
        ]

        for clothData in clothingItems {
            let clothBase64 = clothData.base64EncodedString()
            content.append(["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(clothBase64)"]])
        }

        content.append(["type": "text", "text": """
        请将图片中的服装自然地穿到人物身上，要求：
        1. 保持人物姿势和面部特征不变
        2. 服装自然垂感，贴合身形
        3. 保持服装原有颜色和图案
        4. 光线和阴影自然过渡
        返回试穿效果图。
        """])

        let requestBody: [String: Any] = [
            "model": "qwen-vl-plus",
            "messages": [
                ["role": "user", "content": content]
            ],
            "max_tokens": 1500
        ]

        guard let url = URL(string: dashscopeBaseURL) else {
            throw AliyunError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw AliyunError.apiError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1): \(errorBody)")
        }

        // Parse the image URL from response and download it
        let dashResponse = try JSONDecoder().decode(DashScopeResponse.self, from: data)
        guard let content = dashResponse.choices.first?.message.content else {
            throw AliyunError.parseError
        }

        // If the response contains a URL, fetch it
        if let imageURL = extractImageURL(from: content),
           let url = URL(string: imageURL) {
            let (imageData, _) = try await URLSession.shared.data(from: url)
            return imageData
        }

        // If the response is base64
        if let base64 = extractBase64(from: content),
           let imageData = Data(base64Encoded: base64) {
            return imageData
        }

        throw AliyunError.parseError
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
