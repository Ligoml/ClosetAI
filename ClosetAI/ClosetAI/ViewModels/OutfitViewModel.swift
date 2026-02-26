import Foundation
import SwiftUI
import Combine

class OutfitViewModel: ObservableObject {
    @Published var recommendedOutfits: [OutfitSuggestion] = []
    @Published var savedOutfits: [Outfit] = []
    @Published var selectedOccasion: String = "日常"
    @Published var isGenerating: Bool = false
    @Published var errorMessage: String?
    @Published var isTryingOn: Bool = false
    @Published var tryOnResultImage: UIImage?

    private let persistence = PersistenceController.shared
    private let imageService = ImageProcessingService.shared
    private let aliyunService = AliyunService.shared

    let occasions = Occasion.allCases.map { $0.rawValue }

    init() {
        loadSavedOutfits()
    }

    func loadSavedOutfits() {
        savedOutfits = persistence.fetchOutfits()
    }

    // MARK: - Recommend Outfits

    func generateRecommendations(from items: [ClothingItem]) {
        isGenerating = true
        errorMessage = nil

        let availableItems = items.filter { !$0.isSoftDeleted }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let suggestions = self.computeOutfits(from: availableItems, occasion: self.selectedOccasion)

            DispatchQueue.main.async {
                self.recommendedOutfits = suggestions
                self.isGenerating = false
            }
        }
    }

    private func computeOutfits(from items: [ClothingItem], occasion: String) -> [OutfitSuggestion] {
        guard items.count >= 2 else { return [] }

        // Soft filter: occasion match (fall back to all if none match)
        var filtered = items.filter { item in
            let occasions = (item.occasions as? [String]) ?? []
            return occasions.isEmpty || occasions.contains(occasion)
        }
        if filtered.isEmpty { filtered = items }

        // Separate by category
        let tops      = filtered.filter { $0.category == "上装" }
        let bottoms   = filtered.filter { $0.category == "下装" }
        let outerwear = filtered.filter { $0.category == "外套" }
        let dresses   = filtered.filter { $0.category == "连衣裙" }
        let shoes     = filtered.filter { $0.category == "鞋子" }
        // "其他" 或未打标的衣物
        let others    = filtered.filter {
            let cat = $0.category ?? ""
            return !["上装","下装","外套","连衣裙","鞋子","包包","配饰"].contains(cat)
        }

        var suggestions: [OutfitSuggestion] = []
        let maxOutfits = 3

        // Outfit type 1: dress + shoes
        if !dresses.isEmpty {
            let dress = selectBestItem(from: dresses)
            var combo = [dress]
            if !shoes.isEmpty { combo.append(selectBestItem(from: shoes, avoiding: combo)) }
            suggestions.append(OutfitSuggestion(items: combo, score: scoreOutfit(items: combo)))
        }

        // Outfit type 2: top + bottom (+ optional outerwear + shoes)
        if !tops.isEmpty && !bottoms.isEmpty && suggestions.count < maxOutfits {
            let top    = selectBestItem(from: tops)
            let bottom = selectBestItem(from: bottoms, avoiding: [top])
            var combo  = [top, bottom]
            if !outerwear.isEmpty && Bool.random() {
                combo.append(selectBestItem(from: outerwear, avoiding: combo))
            }
            if !shoes.isEmpty { combo.append(selectBestItem(from: shoes, avoiding: combo)) }
            suggestions.append(OutfitSuggestion(items: combo, score: scoreOutfit(items: combo)))
        }

        // Outfit type 3: different top+bottom combo
        if !tops.isEmpty && !bottoms.isEmpty && suggestions.count < maxOutfits {
            let usedIDs  = Set(suggestions.flatMap { $0.items.compactMap { $0.id } })
            let freeTops = tops.filter    { !usedIDs.contains($0.id ?? UUID()) }
            let freeBots = bottoms.filter { !usedIDs.contains($0.id ?? UUID()) }
            let top    = selectBestItem(from: freeTops.isEmpty ? tops : freeTops)
            let bottom = selectBestItem(from: freeBots.isEmpty ? bottoms : freeBots, avoiding: [top])
            var combo  = [top, bottom]
            if !shoes.isEmpty { combo.append(selectBestItem(from: shoes, avoiding: combo)) }
            suggestions.append(OutfitSuggestion(items: combo, score: scoreOutfit(items: combo)))
        }

        // ── 兜底：当衣物没有标准分类时，随机从所有衣物中组合 ──
        if suggestions.isEmpty && filtered.count >= 2 {
            // 把 others + 未分类的都混进来，最多挑3套
            let pool = filtered
            for _ in 0..<min(maxOutfits, pool.count / 2) {
                let shuffled = pool.shuffled()
                // 每套取 2~3 件，避免重复衣物
                let comboSize = min(3, shuffled.count)
                let combo = Array(shuffled.prefix(comboSize))
                let score = scoreOutfit(items: combo)
                suggestions.append(OutfitSuggestion(items: combo, score: score))
            }
        }

        return suggestions.sorted { $0.score > $1.score }
    }

    private func selectBestItem(from items: [ClothingItem], avoiding: [ClothingItem] = []) -> ClothingItem {
        let avoidIDs = Set(avoiding.compactMap { $0.id })
        let eligible = items.filter { !avoidIDs.contains($0.id ?? UUID()) }
        let pool = eligible.isEmpty ? items : eligible

        // Freshness weighting: prefer items not recently recommended
        let now = Date()
        let scored = pool.map { item -> (ClothingItem, Double) in
            let daysSinceRecommended: Double
            if let last = item.lastRecommendedAt {
                daysSinceRecommended = now.timeIntervalSince(last) / 86400
            } else {
                daysSinceRecommended = 365
            }
            let freshnessScore = min(daysSinceRecommended / 7, 1.0) // Max score after 7 days
            return (item, freshnessScore)
        }

        return scored.max(by: { $0.1 < $1.1 })?.0 ?? pool[0]
    }

    private func scoreOutfit(items: [ClothingItem]) -> Double {
        var score = 0.0

        // Color harmony score
        let allColors = items.flatMap { ($0.colors as? [String]) ?? [] }
        score += colorHarmonyScore(colors: allColors) * 0.4

        // Style consistency (Jaccard similarity)
        let styleSets = items.map { Set(($0.styles as? [String]) ?? []) }
        if styleSets.count > 1 {
            let intersection = styleSets.dropFirst().reduce(styleSets[0]) { $0.intersection($1) }
            let union = styleSets.dropFirst().reduce(styleSets[0]) { $0.union($1) }
            let jaccard = union.isEmpty ? 0.0 : Double(intersection.count) / Double(union.count)
            score += jaccard * 0.4
        }

        // Freshness bonus
        let now = Date()
        let avgFreshness = items.compactMap { item -> Double? in
            guard let last = item.lastRecommendedAt else { return 1.0 }
            return min(now.timeIntervalSince(last) / (86400 * 7), 1.0)
        }.reduce(0, +) / Double(max(items.count, 1))
        score += avgFreshness * 0.2

        return score
    }

    private func colorHarmonyScore(colors: [String]) -> Double {
        // Complementary color pairs (simplified)
        let complementaryPairs: Set<String> = ["黑白", "白黑", "蓝橙", "橙蓝", "红绿", "绿红", "黄紫", "紫黄"]

        var harmonyCount = 0
        for i in 0..<colors.count {
            for j in (i + 1)..<colors.count {
                let pair = colors[i] + colors[j]
                if complementaryPairs.contains(pair) {
                    harmonyCount += 1
                }
                // Neutral colors work with everything
                if colors[i].contains("白") || colors[i].contains("黑") ||
                   colors[i].contains("灰") || colors[j].contains("白") ||
                   colors[j].contains("黑") || colors[j].contains("灰") {
                    harmonyCount += 1
                }
            }
        }
        return min(Double(harmonyCount) / 2.0, 1.0)
    }

    // MARK: - Generate Collage

    func generateCollage(for suggestion: OutfitSuggestion) async -> UIImage? {
        // Sort by category: 上装/连衣裙 → 外套 → 下装 → 鞋子 → others
        let categoryOrder: [String: Int] = [
            "上装": 0, "连衣裙": 0,
            "外套": 1,
            "下装": 2,
            "鞋子": 3,
            "包包": 4, "配饰": 5
        ]
        let sorted = suggestion.items.sorted {
            let a = categoryOrder[$0.category ?? ""] ?? 6
            let b = categoryOrder[$1.category ?? ""] ?? 6
            return a < b
        }

        // Collect image data + descriptions for AI
        var imageDatas: [Data] = []
        var itemDescriptions: [String] = []
        var fallbackItems: [(image: UIImage, category: String)] = []

        for item in sorted {
            let path = item.flatLayImagePath ?? item.originalImagePath ?? ""
            if let image = imageService.loadImage(from: path) {
                fallbackItems.append((image: image, category: item.category ?? ""))
                if let data = image.jpegData(compressionQuality: 0.8) {
                    imageDatas.append(data)
                    let desc = item.subCategory ?? item.category ?? "服装"
                    itemDescriptions.append(desc)
                }
            }
        }

        guard !imageDatas.isEmpty else { return nil }

        // Try AI collage first; fall back to Core Graphics on any error
        do {
            let resultData = try await aliyunService.generateAICollage(
                imageDatas: imageDatas,
                itemDescriptions: itemDescriptions
            )
            if let aiImage = UIImage(data: resultData) {
                return aiImage
            }
        } catch {
            print("AI collage error, falling back to Core Graphics: \(error)")
        }

        // Fallback: Core Graphics collage
        return imageService.generateOutfitCollage(items: fallbackItems)
    }

    // MARK: - Save Outfit

    func saveOutfit(_ suggestion: OutfitSuggestion, collagePath: String, name: String) {
        let itemIDs = suggestion.items.compactMap { $0.id }
        let model = OutfitModel(
            name: name,
            itemIDs: itemIDs,
            occasion: selectedOccasion,
            collagePath: collagePath
        )
        persistence.createOutfit(from: model)

        // Update lastRecommendedAt for each item
        for item in suggestion.items {
            item.lastRecommendedAt = Date()
        }
        persistence.save()
        loadSavedOutfits()
    }

    // MARK: - Delete Outfit

    func deleteOutfit(_ outfit: Outfit) {
        // Delete collage image file if exists
        if let collagePath = outfit.collagePath, !collagePath.isEmpty {
            let resolvedPath = LocalImageView.resolvePath(collagePath)
            try? FileManager.default.removeItem(atPath: resolvedPath)
        }
        persistence.deleteOutfit(outfit)
        loadSavedOutfits()
    }

    // MARK: - Virtual Try-On

    func performVirtualTryOn(personImage: UIImage, items: [ClothingItem]) async {
        await MainActor.run { isTryingOn = true; tryOnResultImage = nil; errorMessage = nil }

        do {
            guard let personData = personImage.jpegData(compressionQuality: 0.8) else { return }

            var clothingDatas: [Data] = []
            for item in items {
                let path = item.flatLayImagePath ?? item.originalImagePath ?? ""
                if let img = imageService.loadImage(from: path),
                   let data = img.jpegData(compressionQuality: 0.8) {
                    clothingDatas.append(data)
                }
            }

            let resultData = try await aliyunService.virtualTryOn(personImageData: personData, clothingItems: clothingDatas)
            let resultImage = UIImage(data: resultData)

            await MainActor.run {
                self.tryOnResultImage = resultImage
                self.isTryingOn = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isTryingOn = false
            }
        }
    }
}

// MARK: - OutfitSuggestion

struct OutfitSuggestion: Identifiable {
    let id = UUID()
    let items: [ClothingItem]
    let score: Double
}
