import SwiftUI

struct LocalImageView: View {
    let path: String?
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(Color(.systemGray3))
                            .font(.system(size: 24))
                    )
            }
        }
        .onAppear { loadImage() }
        .onChange(of: path) { _ in loadImage() }
    }

    private func loadImage() {
        guard let path = path, !path.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let img = UIImage(contentsOfFile: Self.resolvePath(path))
            DispatchQueue.main.async { self.image = img }
        }
    }

    /// 兼容两种存储格式：
    /// 1. 旧版绝对路径（每次重装/更新后沙箱 UUID 变化导致失效）
    /// 2. 新版只存文件名（每次动态拼接当前 Documents 路径）
    static func resolvePath(_ path: String) -> String {
        // 绝对路径且文件存在 → 直接用
        if path.hasPrefix("/") && FileManager.default.fileExists(atPath: path) {
            return path
        }
        // 绝对路径但文件不存在（沙箱路径变了）→ 提取文件名重新拼
        let filename = path.hasPrefix("/") ? (path as NSString).lastPathComponent : path
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(filename).path
    }
}

struct ClothingItemCard: View {
    let item: ClothingItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LocalImageView(path: item.flatLayImagePath ?? item.originalImagePath)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            if let category = item.subCategory ?? item.category, !category.isEmpty {
                Text(category)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            let colors = (item.colors as? [String]) ?? []
            if !colors.isEmpty {
                Text(colors.prefix(2).joined(separator: " · "))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
