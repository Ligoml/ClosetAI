import Foundation
import SwiftUI
import Combine

class OutfitViewModel: ObservableObject {
    @Published var savedOutfits: [Outfit] = []
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

    // MARK: - Occasion Grouping (v2.0)

    var occupiedOccasions: [String] {
        let used = Set(savedOutfits.compactMap { $0.occasion })
        return occasions.filter { used.contains($0) }
    }

    func outfits(for occasion: String) -> [Outfit] {
        savedOutfits.filter { $0.occasion == occasion }
    }

    // MARK: - Generate Collage

    func generateCollage(for suggestion: OutfitSuggestion) async -> UIImage? {
        let categoryOrder: [String: Int] = [
            "上装": 0, "连衣裙": 0, "外套": 1, "下装": 2, "鞋子": 3, "包包": 4, "配饰": 5
        ]
        let sorted = suggestion.items.sorted {
            (categoryOrder[$0.category ?? ""] ?? 6) < (categoryOrder[$1.category ?? ""] ?? 6)
        }

        var imageDatas: [Data] = []
        var itemDescriptions: [String] = []
        var fallbackItems: [(image: UIImage, category: String)] = []

        for item in sorted {
            let path = item.flatLayImagePath ?? item.originalImagePath ?? ""
            if let image = imageService.loadImage(from: path) {
                fallbackItems.append((image: image, category: item.category ?? ""))
                if let data = image.jpegData(compressionQuality: 0.8) {
                    imageDatas.append(data)
                    itemDescriptions.append(item.subCategory ?? item.category ?? "服装")
                }
            }
        }

        guard !imageDatas.isEmpty else { return nil }

        do {
            if imageDatas.count == 2 {
                // wan2.6 接口对恰好 2 张图的多图输入支持有限，
                // 改为：先 Core Graphics 合成 → 再 AI 单图增强
                let cgComposite = imageService.generateOutfitCollage(items: fallbackItems)
                if let cgData = cgComposite.jpegData(compressionQuality: 0.85) {
                    let enhancedData = try await aliyunService.enhanceCollage(baseCollageData: cgData)
                    if let enhanced = UIImage(data: enhancedData) { return enhanced }
                }
                return cgComposite
            } else {
                let resultData = try await aliyunService.generateAICollage(
                    imageDatas: imageDatas,
                    itemDescriptions: itemDescriptions
                )
                if let aiImage = UIImage(data: resultData) { return aiImage }
            }
        } catch {
            print("AI collage error, falling back to Core Graphics: \(error)")
        }

        return imageService.generateOutfitCollage(items: fallbackItems)
    }

    // MARK: - Save Outfit

    func saveOutfit(_ suggestion: OutfitSuggestion, collagePath: String, name: String, occasion: String, tryOnResult: UIImage? = nil) {
        let itemIDs = suggestion.items.compactMap { $0.id }
        let model = OutfitModel(
            name: name,
            itemIDs: itemIDs,
            occasion: occasion,
            collagePath: collagePath
        )
        let newOutfit = persistence.createOutfit(from: model)

        // 若同时生成了上身图，一并写入
        if let tryOnImage = tryOnResult {
            let filename = "\(newOutfit.id?.uuidString ?? UUID().uuidString)_tryon.jpg"
            if let path = imageService.saveImageToDocuments(tryOnImage, filename: filename) {
                newOutfit.tryOnResultPath = path
            }
        }

        for item in suggestion.items {
            item.lastRecommendedAt = Date()
        }
        persistence.save()
        loadSavedOutfits()
        NotificationCenter.default.post(name: .closetAIOutfitsDidChange, object: nil)
    }

    // MARK: - Update Outfit

    func updateOutfit(_ outfit: Outfit, name: String, occasion: String) {
        outfit.name = name
        outfit.occasion = occasion
        persistence.save()
        loadSavedOutfits()
        NotificationCenter.default.post(name: .closetAIOutfitsDidChange, object: nil)
    }

    // MARK: - Delete Outfit

    func deleteOutfit(_ outfit: Outfit) {
        if let collagePath = outfit.collagePath, !collagePath.isEmpty {
            let resolvedPath = LocalImageView.resolvePath(collagePath)
            try? FileManager.default.removeItem(atPath: resolvedPath)
        }
        if let tryOnPath = outfit.tryOnResultPath, !tryOnPath.isEmpty {
            let resolvedPath = LocalImageView.resolvePath(tryOnPath)
            try? FileManager.default.removeItem(atPath: resolvedPath)
        }
        persistence.deleteOutfit(outfit)
        loadSavedOutfits()
        NotificationCenter.default.post(name: .closetAIOutfitsDidChange, object: nil)
    }

    // MARK: - Save Try-On Result

    func saveTryOnResult(_ image: UIImage, for outfit: Outfit) {
        let filename = "\(outfit.id?.uuidString ?? UUID().uuidString)_tryon.jpg"
        if let oldPath = outfit.tryOnResultPath, !oldPath.isEmpty {
            try? FileManager.default.removeItem(atPath: LocalImageView.resolvePath(oldPath))
        }
        if let path = imageService.saveImageToDocuments(image, filename: filename) {
            outfit.tryOnResultPath = path
            persistence.save()
            loadSavedOutfits()
        }
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
            let resultData = try await aliyunService.virtualTryOn(
                personImageData: personData,
                clothingItems: clothingDatas
            )
            let resultImage = UIImage(data: resultData)
            await MainActor.run { self.tryOnResultImage = resultImage; self.isTryingOn = false }
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription; self.isTryingOn = false }
        }
    }
}

// MARK: - OutfitSuggestion

struct OutfitSuggestion: Identifiable {
    let id = UUID()
    let items: [ClothingItem]
    let score: Double
}
