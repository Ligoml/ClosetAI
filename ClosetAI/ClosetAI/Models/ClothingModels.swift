import Foundation
import SwiftUI

// MARK: - Enums

enum ClothingCategory: String, CaseIterable, Codable {
    case top = "上装"
    case bottom = "下装"
    case outerwear = "外套"
    case dress = "连衣裙"
    case shoes = "鞋子"
    case bag = "包包"
    case accessory = "配饰"
    case other = "其他"
}

enum ClothingPattern: String, CaseIterable, Codable {
    case solid = "纯色"
    case striped = "条纹"
    case plaid = "格纹"
    case floral = "花卉"
    case geometric = "几何"
    case abstract = "抽象"
    case animal = "动物纹"
    case other = "其他"
}

enum ClothingStyle: String, CaseIterable, Codable {
    case casual = "休闲"
    case formal = "正式"
    case sport = "运动"
    case elegant = "优雅"
    case streetwear = "街头"
    case minimalist = "简约"
    case vintage = "复古"
    case bohemian = "波西米亚"
}

enum Season: String, CaseIterable, Codable {
    case spring = "春"
    case summer = "夏"
    case autumn = "秋"
    case winter = "冬"
    case allSeason = "四季"
}

enum Occasion: String, CaseIterable, Codable {
    case daily = "日常"
    case work = "上班"
    case date = "约会"
    case sport = "运动"
    case formal = "正式"
    case party = "派对"
    case travel = "旅行"
}

// MARK: - ClothingTags (from AI response)

struct ClothingTags: Codable {
    var category: String
    var subCategory: String
    var colors: [String]
    var pattern: String
    var styles: [String]
    var seasons: [String]
    var occasions: [String]
    var notes: String

    enum CodingKeys: String, CodingKey {
        case category = "大类"
        case subCategory = "小类"
        case colors = "主色调"
        case pattern = "图案"
        case styles = "风格"
        case seasons = "季节"
        case occasions = "场合"
        case notes = "备注"
    }

    init() {
        category = ""
        subCategory = ""
        colors = []
        pattern = ""
        styles = []
        seasons = []
        occasions = []
        notes = ""
    }

    /// AI 可能返回字符串或数组，统一解码为 [String]
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        category   = (try? container.decode(String.self, forKey: .category))   ?? ""
        subCategory = (try? container.decode(String.self, forKey: .subCategory)) ?? ""
        pattern    = (try? container.decode(String.self, forKey: .pattern))    ?? ""
        notes      = (try? container.decode(String.self, forKey: .notes))      ?? ""
        colors     = ClothingTags.decodeStringOrArray(container, key: .colors)
        styles     = ClothingTags.decodeStringOrArray(container, key: .styles)
        seasons    = ClothingTags.decodeStringOrArray(container, key: .seasons)
        occasions  = ClothingTags.decodeStringOrArray(container, key: .occasions)
    }

    /// 兼容数组和逗号/顿号分隔的字符串两种格式
    private static func decodeStringOrArray(
        _ container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys
    ) -> [String] {
        if let arr = try? container.decode([String].self, forKey: key) {
            return arr.flatMap { $0.components(separatedBy: CharacterSet(charactersIn: "、,，|")) }
                      .map { $0.trimmingCharacters(in: .whitespaces) }
                      .filter { !$0.isEmpty }
        }
        if let str = try? container.decode(String.self, forKey: key) {
            return str.components(separatedBy: CharacterSet(charactersIn: "、,，|"))
                      .map { $0.trimmingCharacters(in: .whitespaces) }
                      .filter { !$0.isEmpty }
        }
        return []
    }
}

// MARK: - ClothingItem (Swift model mirroring Core Data entity)

struct ClothingItemModel: Identifiable {
    let id: UUID
    var originalImagePath: String
    var flatLayImagePath: String
    var ossKey: String
    var category: String
    var subCategory: String
    var colors: [String]
    var pattern: String
    var styles: [String]
    var seasons: [String]
    var occasions: [String]
    var wearCount: Int
    var lastWornDate: Date?
    var lastRecommendedAt: Date?
    var notes: String
    var isSoftDeleted: Bool
    var createdAt: Date

    init(id: UUID = UUID(),
         originalImagePath: String = "",
         flatLayImagePath: String = "",
         ossKey: String = "",
         category: String = "",
         subCategory: String = "",
         colors: [String] = [],
         pattern: String = "",
         styles: [String] = [],
         seasons: [String] = [],
         occasions: [String] = [],
         wearCount: Int = 0,
         lastWornDate: Date? = nil,
         lastRecommendedAt: Date? = nil,
         notes: String = "",
         isSoftDeleted: Bool = false,
         createdAt: Date = Date()) {
        self.id = id
        self.originalImagePath = originalImagePath
        self.flatLayImagePath = flatLayImagePath
        self.ossKey = ossKey
        self.category = category
        self.subCategory = subCategory
        self.colors = colors
        self.pattern = pattern
        self.styles = styles
        self.seasons = seasons
        self.occasions = occasions
        self.wearCount = wearCount
        self.lastWornDate = lastWornDate
        self.lastRecommendedAt = lastRecommendedAt
        self.notes = notes
        self.isSoftDeleted = isSoftDeleted
        self.createdAt = createdAt
    }
}

// MARK: - Outfit

struct OutfitModel: Identifiable {
    let id: UUID
    var name: String
    var itemIDs: [UUID]
    var occasion: String
    var collagePath: String
    var isFavorite: Bool
    var createdAt: Date

    init(id: UUID = UUID(),
         name: String = "",
         itemIDs: [UUID] = [],
         occasion: String = "",
         collagePath: String = "",
         isFavorite: Bool = false,
         createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.itemIDs = itemIDs
        self.occasion = occasion
        self.collagePath = collagePath
        self.isFavorite = isFavorite
        self.createdAt = createdAt
    }
}

// MARK: - WearLog

struct WearLogModel: Identifiable {
    let id: UUID
    var outfitID: UUID?
    var itemIDs: [UUID]
    var wornDate: Date
    var note: String

    init(id: UUID = UUID(),
         outfitID: UUID? = nil,
         itemIDs: [UUID] = [],
         wornDate: Date = Date(),
         note: String = "") {
        self.id = id
        self.outfitID = outfitID
        self.itemIDs = itemIDs
        self.wornDate = wornDate
        self.note = note
    }
}
