import SwiftUI
import PhotosUI

struct SettingsView: View {
    @StateObject private var settingsVM = SettingsViewModel()
    @EnvironmentObject var wardrobeVM: WardrobeViewModel

    @State private var modelPhoto: UIImage?
    @State private var showModelPhotoPicker = false

    var body: some View {
        NavigationView {
            List {
                // API Configuration
                apiSection

                // Model Photo
                modelPhotoSection

                // Statistics
                statisticsSection

                // Data Management
                dataSection

                // App Info
                infoSection
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .alert("已保存", isPresented: $settingsVM.showSavedAlert) {
                Button("确定") {}
            }
            .onAppear {
                modelPhoto = settingsVM.loadModelPhoto()
            }
        }
        .sheet(isPresented: $showModelPhotoPicker) {
            PhotoPickerView(images: Binding(
                get: { modelPhoto.map { [$0] } ?? [] },
                set: { images in
                    if let img = images.first {
                        modelPhoto = img
                        settingsVM.saveModelPhoto(img)
                    }
                }
            ))
        }
    }

    // MARK: - Model Photo Section

    private var modelPhotoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                if let photo = modelPhoto {
                    HStack(spacing: 16) {
                        Image(uiImage: photo)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 72, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray4), lineWidth: 0.5))

                        VStack(alignment: .leading, spacing: 8) {
                            Text("已设置模特图")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("虚拟试穿时将自动使用此图片")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 12) {
                                Button("更换") {
                                    showModelPhotoPicker = true
                                }
                                .font(.subheadline)
                                .foregroundColor(AppColors.accent)

                                Button("删除") {
                                    settingsVM.clearModelPhoto()
                                    modelPhoto = nil
                                }
                                .font(.subheadline)
                                .foregroundColor(.red)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Button {
                        showModelPhotoPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.rectangle.badge.plus")
                                .font(.title2)
                                .foregroundColor(AppColors.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("上传模特图")
                                    .foregroundColor(.primary)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("虚拟试穿时无需每次重新上传")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(Color(.systemGray3))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("默认模特图")
        } footer: {
            Text("设置后，虚拟试穿页面将自动加载此模特图，省去每次手动选择的步骤。")
                .font(.caption)
        }
    }

    // MARK: - Sections

    private var apiSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("DashScope API Key", systemImage: "key")
                    .font(.subheadline)
                    .fontWeight(.medium)
                SecureField("请输入 API Key", text: $settingsVM.dashscopeAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("保存 API Key") {
                    settingsVM.saveAPIKey()
                }
                .foregroundColor(AppColors.accent)
                .font(.subheadline)
            }
            .padding(.vertical, 4)

            NavigationLink(destination: APIGuideView()) {
                Label("如何获取 API Key", systemImage: "questionmark.circle")
                    .font(.subheadline)
            }
        } header: {
            Text("阿里云配置")
        } footer: {
            Text("API Key 安全存储在设备 Keychain 中，不会上传至任何服务器。")
                .font(.caption)
        }
    }

    private var statisticsSection: some View {
        Section {
            HStack {
                Label("衣物总数", systemImage: "tshirt")
                Spacer()
                Text("\(wardrobeVM.totalCount) 件")
                    .foregroundColor(.secondary)
            }

            NavigationLink(destination: ColorDistributionView(distribution: wardrobeVM.colorDistribution)) {
                Label("颜色分布", systemImage: "paintpalette")
            }

            NavigationLink(destination: NotWornRecentlyView(items: wardrobeVM.notWornRecently)) {
                HStack {
                    Label("近90天未穿", systemImage: "clock")
                    Spacer()
                    Text("\(wardrobeVM.notWornRecently.count) 件")
                        .foregroundColor(wardrobeVM.notWornRecently.count > 5 ? .orange : .secondary)
                }
            }
        } header: {
            Text("统计面板")
        }
    }

    private var dataSection: some View {
        Section {
            Button(role: .destructive) {
                settingsVM.showClearConfirm = true
            } label: {
                Label("清空已删除的衣物", systemImage: "trash")
            }
            .alert("确认清空", isPresented: $settingsVM.showClearConfirm) {
                Button("清空", role: .destructive) {
                    settingsVM.clearDeletedItems()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("已软删除的衣物将被永久移除，此操作不可撤销。")
            }
        } header: {
            Text("数据管理")
        }
    }

    private var infoSection: some View {
        Section {
            HStack {
                Label("版本", systemImage: "info.circle")
                Spacer()
                Text("1.0.0")
                    .foregroundColor(.secondary)
            }

            HStack {
                Label("平台", systemImage: "iphone")
                Spacer()
                Text("iOS 16+")
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("关于")
        }
    }
}

// MARK: - SettingsViewModel

class SettingsViewModel: ObservableObject {
    @Published var dashscopeAPIKey: String = ""
    @Published var showSavedAlert = false
    @Published var showClearConfirm = false

    init() {
        dashscopeAPIKey = KeychainHelper.load(for: KeychainKey.dashscopeAPIKey) ?? ""
    }

    func saveAPIKey() {
        KeychainHelper.save(dashscopeAPIKey, for: KeychainKey.dashscopeAPIKey)
        showSavedAlert = true
    }

    // MARK: - Model Photo

    private let modelPhotoKey = "closetai.modelPhotoFilename"
    private let modelPhotoFilename = "model_photo.jpg"

    func loadModelPhoto() -> UIImage? {
        guard UserDefaults.standard.string(forKey: modelPhotoKey) != nil else { return nil }
        return ImageProcessingService.shared.loadImage(from: modelPhotoFilename)
    }

    func saveModelPhoto(_ image: UIImage) {
        _ = ImageProcessingService.shared.saveImageToDocuments(image, filename: modelPhotoFilename)
        UserDefaults.standard.set(modelPhotoFilename, forKey: modelPhotoKey)
    }

    func clearModelPhoto() {
        let path = LocalImageView.resolvePath(modelPhotoFilename)
        try? FileManager.default.removeItem(atPath: path)
        UserDefaults.standard.removeObject(forKey: modelPhotoKey)
    }

    func clearDeletedItems() {
        let items = PersistenceController.shared.fetchClothingItems(includeDeleted: true).filter { $0.isSoftDeleted }
        for item in items {
            if let path = item.originalImagePath {
                try? FileManager.default.removeItem(atPath: LocalImageView.resolvePath(path))
            }
            if let path = item.flatLayImagePath {
                try? FileManager.default.removeItem(atPath: LocalImageView.resolvePath(path))
            }
            PersistenceController.shared.deleteClothingItem(item, soft: false)
        }
    }
}

// MARK: - API Guide View

struct APIGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Group {
                    Text("如何获取 API Key")
                        .font(.title2)
                        .fontWeight(.bold)

                    stepView(number: 1, title: "访问阿里云百炼控制台",
                             description: "打开 Safari，访问：\nhttps://bailian.console.aliyun.com")

                    stepView(number: 2, title: "登录阿里云账号",
                             description: "使用阿里云账号登录，若没有账号可免费注册")

                    stepView(number: 3, title: "创建 API Key",
                             description: "进入控制台后，点击右上角头像或左侧菜单中的「API-KEY 管理」，点击「创建 API Key」")

                    stepView(number: 4, title: "复制并填入",
                             description: "复制生成的 API Key，粘贴到上方输入框，点击「保存 API Key」即可")
                }
                .padding(.horizontal, 16)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("计费说明")
                        .font(.headline)
                    Text("• 自动打标（qwen-vl-plus）：根据实际用量计费\n• 穿搭平铺图 / 虚拟试穿（wan2.6-image）：根据实际用量计费\n• 新用户通常有免费额度可使用")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    // 可点击的链接
                    Link(destination: URL(string: "https://bailian.console.aliyun.com/cn-beijing/?tab=app#/api-key")!) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                            Text("直接跳转到 API Key 管理页面")
                        }
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 16)
        }
        .navigationTitle("API Key 指南")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stepView(number: Int, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(AppColors.accent)
                .frame(width: 28, height: 28)
                .overlay(
                    Text("\(number)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Color Distribution View

struct ColorDistributionView: View {
    let distribution: [String: Int]

    var sortedColors: [(String, Int)] {
        distribution.sorted { $0.value > $1.value }
    }

    var total: Int {
        distribution.values.reduce(0, +)
    }

    var body: some View {
        List {
            ForEach(sortedColors, id: \.0) { color, count in
                HStack {
                    Circle()
                        .fill(colorForName(color))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color(.systemGray4), lineWidth: 0.5))
                    Text(color)
                    Spacer()
                    Text("\(count) 件")
                        .foregroundColor(.secondary)

                    // Progress bar
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.accent.opacity(0.3))
                        .frame(width: CGFloat(count) / CGFloat(max(total, 1)) * 80, height: 8)
                }
            }
        }
        .navigationTitle("颜色分布")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func colorForName(_ name: String) -> Color {
        switch name {
        case "黑", "黑色": return .black
        case "白", "白色": return .white
        case "灰", "灰色": return .gray
        case "红", "红色": return .red
        case "蓝", "蓝色": return .blue
        case "绿", "绿色": return .green
        case "黄", "黄色": return .yellow
        case "橙", "橙色": return .orange
        case "粉", "粉色": return .pink
        case "紫", "紫色": return .purple
        case "棕", "棕色", "咖色": return .brown
        default: return .gray
        }
    }
}

// MARK: - Not Worn Recently View

struct NotWornRecentlyView: View {
    let items: [ClothingItem]

    var body: some View {
        List {
            if items.isEmpty {
                Text("近 90 天内所有衣物都有穿着记录")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(items) { item in
                    HStack(spacing: 12) {
                        LocalImageView(path: item.flatLayImagePath ?? item.originalImagePath)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.subCategory ?? item.category ?? "未知")
                                .fontWeight(.medium)
                            Text(item.lastWornDate.map { "上次穿着: \(formatDate($0))" } ?? "从未穿着")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
        }
        .navigationTitle("近90天未穿")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: date)
    }
}
