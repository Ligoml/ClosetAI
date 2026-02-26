import Foundation
import SwiftUI
import Combine
import CoreData

class WardrobeViewModel: ObservableObject {
    @Published var items: [ClothingItem] = []
    @Published var filteredItems: [ClothingItem] = []
    @Published var selectedCategory: String = "全部"
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showDeletedItems: Bool = false

    private var cancellables = Set<AnyCancellable>()
    private let persistence = PersistenceController.shared
    private let imageService = ImageProcessingService.shared
    private let aliyunService = AliyunService.shared

    let categories = ["全部"] + ClothingCategory.allCases.map { $0.rawValue }

    init() {
        loadItems()
        setupSearch()
    }

    func loadItems() {
        items = persistence.fetchClothingItems(includeDeleted: showDeletedItems)
        applyFilters()
    }

    private func setupSearch() {
        Publishers.CombineLatest3($searchText, $selectedCategory, $items)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                self?.applyFilters()
            }
            .store(in: &cancellables)
    }

    private func applyFilters() {
        var result = items

        if selectedCategory != "全部" {
            result = result.filter { $0.category == selectedCategory }
        }

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

    // MARK: - Add Item with AI Processing

    func processAndAddItem(image: UIImage) async {
        await MainActor.run { isLoading = true; errorMessage = nil }

        do {
            // 1. Preprocess
            let preprocessed = imageService.preprocessImage(image)

            // 2. Remove background
            let noBG = await imageService.removeBackground(from: preprocessed)

            // 3. Generate flat lay
            let flatLay = imageService.generateFlatLayImage(from: noBG)

            // 4. Quality check
            guard imageService.checkQuality(of: flatLay) else {
                await MainActor.run {
                    errorMessage = "图片质量不佳，请重新拍摄"
                    isLoading = false
                }
                return
            }

            // 5. Save images
            let itemID = UUID()
            let originalFilename = "\(itemID.uuidString)_original.jpg"
            let flatLayFilename = "\(itemID.uuidString)_flatlay.jpg"

            guard let originalPath = imageService.saveImageToDocuments(image, filename: originalFilename),
                  let flatLayPath = imageService.saveImageToDocuments(flatLay, filename: flatLayFilename) else {
                throw NSError(domain: "ClosetAI", code: -1, userInfo: [NSLocalizedDescriptionKey: "保存图片失败"])
            }

            // 6. Auto-tag with AI
            var tags = ClothingTags()
            if let imageData = image.jpegData(compressionQuality: 0.8) {
                do {
                    tags = try await aliyunService.autoTagClothing(imageData: imageData)
                } catch {
                    // Non-fatal: use empty tags, user can edit manually
                    print("Auto-tag error: \(error)")
                }
            }

            // 7. Create Core Data record
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

            await MainActor.run {
                self.loadItems()
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
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
        // Delete associated files (resolve path in case only filename is stored)
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

    // MARK: - Statistics

    var totalCount: Int { items.filter { !$0.isSoftDeleted }.count }

    var colorDistribution: [String: Int] {
        var dist: [String: Int] = [:]
        for item in items where !item.isSoftDeleted {
            let colors = (item.colors as? [String]) ?? []
            for color in colors {
                dist[color, default: 0] += 1
            }
        }
        return dist
    }

    var notWornRecently: [ClothingItem] {
        let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        return items.filter { item in
            !item.isSoftDeleted && (item.lastWornDate == nil || item.lastWornDate! < ninetyDaysAgo)
        }
    }
}
