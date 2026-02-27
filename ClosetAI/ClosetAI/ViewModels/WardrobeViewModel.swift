import Foundation
import SwiftUI
import Combine
import CoreData

extension Notification.Name {
    static let closetAIOutfitsDidChange = Notification.Name("closetAIOutfitsDidChange")
}

class WardrobeViewModel: ObservableObject {
    @Published var items: [ClothingItem] = []
    @Published var filteredItems: [ClothingItem] = []
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published private(set) var savedOutfits: [Outfit] = []

    private var cancellables = Set<AnyCancellable>()
    private let persistence = PersistenceController.shared
    private let imageService = ImageProcessingService.shared
    private let aliyunService = AliyunService.shared

    init() {
        loadItems()
        setupSearch()
        NotificationCenter.default.addObserver(
            self, selector: #selector(outfitsDidChange),
            name: .closetAIOutfitsDidChange, object: nil
        )
    }

    func loadItems() {
        items = persistence.fetchClothingItems(includeDeleted: false)
        savedOutfits = persistence.fetchOutfits()
        applyFilters()
    }

    @objc private func outfitsDidChange() {
        savedOutfits = persistence.fetchOutfits()
    }

    private func setupSearch() {
        Publishers.CombineLatest($searchText, $items)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.applyFilters() }
            .store(in: &cancellables)
    }

    private func applyFilters() {
        var result = items.filter { !$0.isSoftDeleted }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                ($0.category?.lowercased().contains(query) == true) ||
                ($0.subCategory?.lowercased().contains(query) == true) ||
                ($0.notes?.lowercased().contains(query) == true) ||
                (($0.colors as? [String])?.joined().lowercased().contains(query) == true) ||
                (($0.styles as? [String])?.joined().lowercased().contains(query) == true)
            }
        }
        filteredItems = result
    }

    // MARK: - Section Helpers

    func items(inCategories categories: [String]) -> [ClothingItem] {
        items.filter { !$0.isSoftDeleted && categories.contains($0.category ?? "") }
    }

    func otherItems(excludingCategories excluded: [String]) -> [ClothingItem] {
        items.filter { item in
            guard !item.isSoftDeleted else { return false }
            return !excluded.contains(item.category ?? "")
        }
    }

    // MARK: - Idle Logic (v2.0: based on outfit association)

    var idleItemIDs: Set<UUID> {
        let usedIDs = Set(savedOutfits.flatMap { outfit -> [UUID] in
            (outfit.itemIDs ?? "")
                .split(separator: ",")
                .compactMap { UUID(uuidString: String($0)) }
        })
        let allIDs = Set(items.filter { !$0.isSoftDeleted }.compactMap { $0.id })
        return allIDs.subtracting(usedIDs)
    }

    func outfits(containing item: ClothingItem) -> [Outfit] {
        guard let itemID = item.id?.uuidString else { return [] }
        return savedOutfits.filter { outfit in
            (outfit.itemIDs ?? "")
                .split(separator: ",")
                .map { String($0) }
                .contains(itemID)
        }
    }

    // MARK: - Statistics

    var totalCount: Int { items.filter { !$0.isSoftDeleted }.count }
    var idleCount: Int { idleItemIDs.count }

    var notWornRecently: [ClothingItem] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        return items.filter { item in
            guard !item.isSoftDeleted else { return false }
            guard let lastWorn = item.lastWornDate else { return true }
            return lastWorn < cutoff
        }
    }

    var colorDistribution: [String: Int] {
        var dist: [String: Int] = [:]
        for item in items where !item.isSoftDeleted {
            for color in (item.colors as? [String]) ?? [] {
                dist[color, default: 0] += 1
            }
        }
        return dist
    }

    // MARK: - Add Item with AI Processing

    func processAndAddItem(image: UIImage) async {
        await MainActor.run { isLoading = true; errorMessage = nil }
        do {
            let preprocessed = imageService.preprocessImage(image)
            let noBG = await imageService.removeBackground(from: preprocessed)
            let flatLay = imageService.generateFlatLayImage(from: noBG)
            guard imageService.checkQuality(of: flatLay) else {
                await MainActor.run { errorMessage = "图片质量不佳，请重新拍摄"; isLoading = false }
                return
            }
            let itemID = UUID()
            let originalFilename = "\(itemID.uuidString)_original.jpg"
            let flatLayFilename = "\(itemID.uuidString)_flatlay.jpg"
            guard let originalPath = imageService.saveImageToDocuments(image, filename: originalFilename),
                  let flatLayPath = imageService.saveImageToDocuments(flatLay, filename: flatLayFilename) else {
                throw NSError(domain: "ClosetAI", code: -1, userInfo: [NSLocalizedDescriptionKey: "保存图片失败"])
            }
            var tags = ClothingTags()
            if let imageData = image.jpegData(compressionQuality: 0.8) {
                do { tags = try await aliyunService.autoTagClothing(imageData: imageData) }
                catch { print("Auto-tag error: \(error)") }
            }
            let model = ClothingItemModel(
                id: itemID,
                originalImagePath: originalPath,
                flatLayImagePath: flatLayPath,
                category: tags.category.isEmpty ? "其他" : tags.category,
                subCategory: tags.subCategory,
                colors: tags.colors,
                pattern: tags.pattern,
                styles: tags.styles,
                seasons: tags.seasons,
                occasions: tags.occasions,
                notes: tags.notes
            )
            persistence.createClothingItem(from: model)
            await MainActor.run { self.loadItems(); self.isLoading = false }
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription; self.isLoading = false }
        }
    }

    func softDelete(_ item: ClothingItem) {
        persistence.deleteClothingItem(item, soft: true)
        loadItems()
    }

    func restore(_ item: ClothingItem) {
        persistence.restoreClothingItem(item)
        loadItems()
    }

    func permanentDelete(_ item: ClothingItem) {
        if let path = item.originalImagePath {
            try? FileManager.default.removeItem(atPath: LocalImageView.resolvePath(path))
        }
        if let path = item.flatLayImagePath {
            try? FileManager.default.removeItem(atPath: LocalImageView.resolvePath(path))
        }
        persistence.deleteClothingItem(item, soft: false)
        loadItems()
    }

    func updateItem(_ item: ClothingItem, tags: ClothingTags) {
        item.category = tags.category
        item.subCategory = tags.subCategory
        item.colors = tags.colors as NSObject
        item.pattern = tags.pattern
        item.styles = tags.styles as NSObject
        item.seasons = tags.seasons as NSObject
        item.occasions = tags.occasions as NSObject
        item.notes = tags.notes
        persistence.save()
        loadItems()
    }

    func recordWear(for item: ClothingItem) {
        item.wearCount += 1
        item.lastWornDate = Date()
        persistence.save()
        let log = WearLogModel(itemIDs: [item.id ?? UUID()])
        persistence.createWearLog(from: log)
        loadItems()
    }
}
