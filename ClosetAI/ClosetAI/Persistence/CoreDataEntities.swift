import Foundation
import CoreData

// MARK: - ClothingItem

@objc(ClothingItem)
public class ClothingItem: NSManagedObject {}

extension ClothingItem {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ClothingItem> {
        return NSFetchRequest<ClothingItem>(entityName: "ClothingItem")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var originalImagePath: String?
    @NSManaged public var flatLayImagePath: String?
    @NSManaged public var ossKey: String?
    @NSManaged public var category: String?
    @NSManaged public var subCategory: String?
    @NSManaged public var colors: NSObject?
    @NSManaged public var pattern: String?
    @NSManaged public var styles: NSObject?
    @NSManaged public var seasons: NSObject?
    @NSManaged public var occasions: NSObject?
    @NSManaged public var wearCount: Int32
    @NSManaged public var lastWornDate: Date?
    @NSManaged public var lastRecommendedAt: Date?
    @NSManaged public var notes: String?
    @NSManaged public var isSoftDeleted: Bool
    @NSManaged public var createdAt: Date?
}

extension ClothingItem: Identifiable {}

// MARK: - Outfit

@objc(Outfit)
public class Outfit: NSManagedObject {}

extension Outfit {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Outfit> {
        return NSFetchRequest<Outfit>(entityName: "Outfit")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var itemIDs: String?
    @NSManaged public var occasion: String?
    @NSManaged public var collagePath: String?
    @NSManaged public var isFavorite: Bool
    @NSManaged public var createdAt: Date?
    @NSManaged public var tryOnResultPath: String?
}

extension Outfit: Identifiable {}

// MARK: - WearLog

@objc(WearLog)
public class WearLog: NSManagedObject {}

extension WearLog {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<WearLog> {
        return NSFetchRequest<WearLog>(entityName: "WearLog")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var outfitID: UUID?
    @NSManaged public var itemIDs: String?
    @NSManaged public var wornDate: Date?
    @NSManaged public var note: String?
}

extension WearLog: Identifiable {}
