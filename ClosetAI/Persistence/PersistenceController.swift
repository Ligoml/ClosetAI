import CoreData
import Foundation

// MARK: - StringArray ValueTransformer
// 将 [String] 安全地序列化为 Data 存入 Core Data Transformable 字段

@objc(StringArrayTransformer)
final class StringArrayTransformer: ValueTransformer {
    override class func transformedValueClass() -> AnyClass { NSData.self }
    override class func allowsReverseTransformation() -> Bool { true }

    override func transformedValue(_ value: Any?) -> Any? {
        guard let array = value as? [String] else { return nil }
        return try? JSONEncoder().encode(array) as NSData
    }

    override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    static let name = NSValueTransformerName("StringArrayTransformer")

    static func register() {
        let transformer = StringArrayTransformer()
        ValueTransformer.setValueTransformer(transformer, forName: name)
    }
}

// MARK: - PersistenceController

class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        // 必须在 loadPersistentStores 之前注册
        StringArrayTransformer.register()
        container = NSPersistentContainer(name: "ClosetAI")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        // 允许轻量级迁移，store schema 有变动时自动处理
        let description = container.persistentStoreDescriptions.first
        description?.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description?.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)

        container.loadPersistentStores { storeDesc, error in
            if let error = error as NSError? {
                print("‼️ Core Data load error: \(error.code) \(error.domain) — \(error.localizedDescription)")
                print("‼️ userInfo: \(error.userInfo)")
                // store 损坏时删除重建（数据清空，但 App 能启动）
                if let storeURL = storeDesc.url {
                    let coordinator = self.container.persistentStoreCoordinator
                    try? coordinator.destroyPersistentStore(at: storeURL, ofType: NSSQLiteStoreType, options: nil)
                    try? coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
                }
            } else {
                print("✅ Core Data loaded: \(storeDesc.url?.lastPathComponent ?? "unknown")")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func save() {
        let context = container.viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("Core Data save error: \(error)")
        }
    }

    // MARK: - ClothingItem CRUD

    func createClothingItem(from model: ClothingItemModel) {
        let context = container.viewContext
        let entity = ClothingItem(context: context)
        entity.id = model.id
        entity.originalImagePath = model.originalImagePath
        entity.flatLayImagePath = model.flatLayImagePath
        entity.ossKey = model.ossKey
        entity.category = model.category
        entity.subCategory = model.subCategory
        entity.colors = model.colors as NSObject
        entity.pattern = model.pattern
        entity.styles = model.styles as NSObject
        entity.seasons = model.seasons as NSObject
        entity.occasions = model.occasions as NSObject
        entity.wearCount = Int32(model.wearCount)
        entity.lastWornDate = model.lastWornDate
        entity.lastRecommendedAt = model.lastRecommendedAt
        entity.notes = model.notes
        entity.isSoftDeleted = model.isSoftDeleted
        entity.createdAt = model.createdAt
        save()
    }

    func fetchClothingItems(includeDeleted: Bool = false) -> [ClothingItem] {
        let request: NSFetchRequest<ClothingItem> = ClothingItem.fetchRequest()
        if !includeDeleted {
            request.predicate = NSPredicate(format: "isSoftDeleted == NO")
        }
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ClothingItem.createdAt, ascending: false)]
        do {
            return try container.viewContext.fetch(request)
        } catch {
            print("Fetch error: \(error)")
            return []
        }
    }

    func deleteClothingItem(_ item: ClothingItem, soft: Bool = true) {
        if soft {
            item.isSoftDeleted = true
        } else {
            container.viewContext.delete(item)
        }
        save()
    }

    func restoreClothingItem(_ item: ClothingItem) {
        item.isSoftDeleted = false
        save()
    }

    // MARK: - Outfit CRUD

    @discardableResult
    func createOutfit(from model: OutfitModel) -> Outfit {
        let context = container.viewContext
        let entity = Outfit(context: context)
        entity.id = model.id
        entity.name = model.name
        entity.itemIDs = model.itemIDs.map { $0.uuidString }.joined(separator: ",")
        entity.occasion = model.occasion
        entity.collagePath = model.collagePath
        entity.isFavorite = model.isFavorite
        entity.createdAt = model.createdAt
        save()
        return entity
    }

    func fetchOutfits() -> [Outfit] {
        let request: NSFetchRequest<Outfit> = Outfit.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Outfit.createdAt, ascending: false)]
        do {
            return try container.viewContext.fetch(request)
        } catch {
            print("Fetch outfits error: \(error)")
            return []
        }
    }

    func deleteOutfit(_ outfit: Outfit) {
        container.viewContext.delete(outfit)
        save()
    }

    // MARK: - WearLog CRUD

    func createWearLog(from model: WearLogModel) {
        let context = container.viewContext
        let entity = WearLog(context: context)
        entity.id = model.id
        entity.outfitID = model.outfitID
        entity.itemIDs = model.itemIDs.map { $0.uuidString }.joined(separator: ",")
        entity.wornDate = model.wornDate
        entity.note = model.note
        save()
    }

    func fetchWearLogs() -> [WearLog] {
        let request: NSFetchRequest<WearLog> = WearLog.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \WearLog.wornDate, ascending: false)]
        do {
            return try container.viewContext.fetch(request)
        } catch {
            print("Fetch logs error: \(error)")
            return []
        }
    }
}
