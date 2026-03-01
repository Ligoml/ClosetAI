import SwiftUI

@main
struct ClosetAIApp: App {
    let persistenceController = PersistenceController.shared

    init() {
        installDefaultModelPhotoIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }

    // 首次启动时将内置模特图复制到 Documents，供 TryOnView 和设置页直接使用
    private func installDefaultModelPhotoIfNeeded() {
        let key = "closetai.modelPhotoFilename"
        let filename = "model_photo.jpg"
        guard UserDefaults.standard.string(forKey: key) == nil,
              let defaultImage = UIImage(named: "model_person") else { return }
        _ = ImageProcessingService.shared.saveImageToDocuments(defaultImage, filename: filename)
        UserDefaults.standard.set(filename, forKey: key)
    }
}
