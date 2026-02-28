import SwiftUI
import PhotosUI

struct SettingsView: View {
    @StateObject private var settingsVM = SettingsViewModel()
    @EnvironmentObject var wardrobeVM: WardrobeViewModel

    @State private var modelPhoto: UIImage?
    @State private var showModelPhotoPicker = false

    var body: some View {
        NavigationStack {
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
            .font(.subheadline)
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
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
                    HStack(spacing: 14) {
                        // 768:1280 = 3:5，按比例等比缩小展示
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray4), lineWidth: 0.5))

                        VStack(alignment: .leading, spacing: 8) {
                            Text("已设置模特图")
                                .fontWeight(.medium)
                            Text("虚拟试穿时将自动使用此图片")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 16) {
                                Button("更换") {
                                    showModelPhotoPicker = true
                                }
                                .foregroundColor(AppColors.accent)
                                .buttonStyle(.borderless)

                                Button("删除") {
                                    settingsVM.clearModelPhoto()
                                    modelPhoto = nil
                                }
                                .foregroundColor(.red)
                                .buttonStyle(.borderless)
                            }
                        }
                        Spacer()
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
                    .fontWeight(.medium)
                SecureField("请输入 API Key", text: $settingsVM.dashscopeAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("保存 API Key") {
                    settingsVM.saveAPIKey()
                }
                .foregroundColor(AppColors.accent)
            }
            .padding(.vertical, 4)

            NavigationLink(destination: APIGuideView()) {
                Label("如何获取 API Key", systemImage: "questionmark.circle")
            }
        } header: {
            Text("阿里云配置")
        } footer: {
            Text("API Key 安全存储在设备 Keychain 中，不会上传至任何服务器。")
                .font(.caption)
        }
    }

    @ViewBuilder private var statisticsSection: some View {
        Section {
            LabeledContent {
                Text("\(wardrobeVM.totalCount) 件")
                    .foregroundColor(.secondary)
            } label: {
                Label("衣物总数", systemImage: "tshirt")
            }

            NavigationLink(destination: ColorDistributionView(distribution: wardrobeVM.colorDistribution)) {
                Label("颜色分布", systemImage: "paintpalette")
            }

            NavigationLink(destination: NotWornRecentlyView(items: wardrobeVM.notWornRecently)) {
                LabeledContent {
                    Text("\(wardrobeVM.notWornRecently.count) 件")
                        .foregroundColor(wardrobeVM.notWornRecently.count > 5 ? .orange : .secondary)
                } label: {
                    Label("近90天未穿", systemImage: "clock")
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

    @ViewBuilder private var infoSection: some View {
        Section {
            LabeledContent {
                Text("1.0.0")
                    .foregroundColor(.secondary)
            } label: {
                Label("版本", systemImage: "info.circle")
            }

            LabeledContent {
                Text("iOS 26+")
                    .foregroundColor(.secondary)
            } label: {
                Label("平台", systemImage: "iphone")
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
                        .font(.title3)
                        .fontWeight(.bold)

                    stepView(number: 1, title: "访问阿里云百炼控制台",
                             description: "打开 Safari，访问：\nhttps://bailian.console.aliyun.com")

                    stepView(number: 2, title: "登录阿里云账号",
                             description: "使用阿里云账号登录，若没有账号可免费注册")

                    stepView(number: 3, title: "创建 API Key",
                             description: "进入控制台后，点击左下角菜单中的「密钥管理」，点击「创建 API Key」")

                    stepView(number: 4, title: "复制并填入",
                             description: "复制生成的 API Key，粘贴到上方输入框，点击「保存 API Key」即可")
                }
                .padding(.horizontal, 16)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("计费说明")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("• 自动打标（qwen-vl-plus）：根据实际用量计费\n• 穿搭平铺图 / 虚拟试穿（wan2.6-image）：根据实际用量计费\n• 新用户通常有免费额度可使用")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    // 可点击的链接
                    Link(destination: URL(string: "https://bailian.console.aliyun.com/cn-beijing/?tab=app#/api-key")!) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                            Text("直接跳转到 API Key 管理页面")
                        }
                        .font(.footnote)
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
                .frame(width: 24, height: 24)
                .overlay(
                    Text("\(number)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.footnote)
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
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color(.systemGray4), lineWidth: 0.5))
                    Text(color)
                    Spacer()
                    Text("\(count) 件")
                        .foregroundColor(.secondary)

                    // Progress bar
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.accent.opacity(0.3))
                        .frame(width: CGFloat(count) / CGFloat(max(total, 1)) * 80, height: 6)
                }
            }
        }
        .font(.subheadline)
        .navigationTitle("颜色分布")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func colorForName(_ name: String) -> Color {
        // 优先精确匹配，再通过关键词模糊匹配
        let n = name

        // 黑色系
        if n.contains("黑") { return .black }

        // 白色系（米白、象牙白、奶白、珍珠白 先于"白"匹配）
        if n.contains("米白") || n.contains("奶白") || n.contains("象牙") || n.contains("珍珠白") {
            return Color(red: 0.97, green: 0.94, blue: 0.88)
        }
        if n.contains("白") { return .white }

        // 米色 / 杏色 / 香槟 / 驼色 / 大地
        if n.contains("米") || n.contains("杏") || n.contains("香槟") || n.contains("驼") || n.contains("大地") {
            return Color(red: 0.91, green: 0.82, blue: 0.68)
        }

        // 卡其 / 沙色
        if n.contains("卡其") || n.contains("沙色") || n.contains("沙褐") {
            return Color(red: 0.76, green: 0.69, blue: 0.49)
        }

        // 灰色系（深灰/浅灰/银灰 先匹配）
        if n.contains("深灰") || n.contains("炭灰") { return Color(red: 0.3, green: 0.3, blue: 0.3) }
        if n.contains("浅灰") || n.contains("银灰") || n.contains("麻灰") { return Color(red: 0.78, green: 0.78, blue: 0.78) }
        if n.contains("灰") { return .gray }

        // 红色系（酒红/深红/玫红/枣红 先匹配）
        if n.contains("酒红") || n.contains("深红") || n.contains("枣红") || n.contains("勃艮第") {
            return Color(red: 0.55, green: 0.1, blue: 0.2)
        }
        if n.contains("玫") || n.contains("粉红") { return Color(red: 1.0, green: 0.4, blue: 0.6) }
        if n.contains("红") { return .red }

        // 蓝色系（藏蓝/深蓝/海军蓝 先匹配）
        if n.contains("藏蓝") || n.contains("深蓝") || n.contains("海军") || n.contains("宝蓝") {
            return Color(red: 0.05, green: 0.1, blue: 0.45)
        }
        if n.contains("浅蓝") || n.contains("天蓝") || n.contains("牛仔") { return Color(red: 0.43, green: 0.65, blue: 0.88) }
        if n.contains("蓝") { return .blue }

        // 绿色系（军绿/墨绿/橄榄绿 先匹配）
        if n.contains("军绿") || n.contains("墨绿") || n.contains("橄榄") || n.contains("深绿") {
            return Color(red: 0.2, green: 0.35, blue: 0.18)
        }
        if n.contains("浅绿") || n.contains("薄荷") { return Color(red: 0.6, green: 0.87, blue: 0.72) }
        if n.contains("绿") { return .green }

        // 黄色系
        if n.contains("姜黄") || n.contains("芥黄") { return Color(red: 0.79, green: 0.66, blue: 0.2) }
        if n.contains("黄") { return .yellow }

        // 橙色系
        if n.contains("橙") || n.contains("南瓜") { return .orange }
        if n.contains("珊瑚") || n.contains("砖红") { return Color(red: 0.91, green: 0.45, blue: 0.35) }

        // 粉色系（薰衣草、淡紫 先匹配）
        if n.contains("薰衣草") || n.contains("淡紫") { return Color(red: 0.73, green: 0.67, blue: 0.90) }
        if n.contains("粉") { return .pink }

        // 紫色系
        if n.contains("紫") { return .purple }

        // 棕色系（咖色、焦糖、巧克力）
        if n.contains("棕") || n.contains("咖") || n.contains("焦糖") || n.contains("巧克力") || n.contains("褐") {
            return .brown
        }

        // 金属色
        if n.contains("金") { return Color(red: 0.85, green: 0.72, blue: 0.35) }
        if n.contains("银") { return Color(red: 0.75, green: 0.75, blue: 0.78) }

        return Color(.systemGray3)
    }
}

// MARK: - Not Worn Recently View

struct NotWornRecentlyView: View {
    let items: [ClothingItem]
    @EnvironmentObject var wardrobeVM: WardrobeViewModel

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
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.subCategory ?? item.category ?? "未知")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(wardrobeVM.lastOutfitDate(for: item).map { "上次穿着: \(formatDate($0))" } ?? "从未加入穿搭")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
        }
        .font(.subheadline)
        .navigationTitle("近90天未穿")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: date)
    }
}
