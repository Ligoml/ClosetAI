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
        if path.hasPrefix("/") && FileManager.default.fileExists(atPath: path) {
            return path
        }
        let filename = path.hasPrefix("/") ? (path as NSString).lastPathComponent : path
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(filename).path
    }
}

// MARK: - Clothing Item Card (v2.0: 140×170, white card, idle badge)

struct ClothingItemCard: View {
    let item: ClothingItem
    var isIdle: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                LocalImageView(path: item.flatLayImagePath ?? item.originalImagePath)
                    .frame(width: 140, height: 140)
                    .clipped()

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.subCategory ?? item.category ?? "")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    let colors = (item.colors as? [String]) ?? []
                    if !colors.isEmpty {
                        Text(colors.prefix(2).joined(separator: " · "))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(height: 30, alignment: .top)
            }
            .frame(width: 140, height: 170)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 1)

            if isIdle {
                Text("未搭配")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(AppColors.idle)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(6)
            }
        }
    }
}
