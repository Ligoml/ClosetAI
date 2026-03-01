import SwiftUI

/// 手动选择衣物组合为穿搭
struct ManualOutfitView: View {
    @EnvironmentObject var outfitVM: OutfitViewModel
    @EnvironmentObject var wardrobeVM: WardrobeViewModel
    @Environment(\.dismiss) var dismiss

    @State private var selectedIDs: Set<UUID> = []
    @State private var filterCategory: String = "全部"
    @State private var createdOutfit: OutfitSuggestion?
    @State private var showMaxItemsAlert = false
    @State private var showNoAPIKeyAlert = false

    private let maxSelectionCount = 4

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    private var availableItems: [ClothingItem] {
        wardrobeVM.items.filter { !($0.isSoftDeleted) }
    }

    private var filteredItems: [ClothingItem] {
        if filterCategory == "全部" { return availableItems }
        return availableItems.filter { $0.category == filterCategory }
    }

    private var selectedItems: [ClothingItem] {
        availableItems.filter { selectedIDs.contains($0.id ?? UUID()) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category filter chips
                categoryFilter

                // Grid of all clothing items
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredItems) { item in
                            ItemSelectCell(
                                item: item,
                                isSelected: selectedIDs.contains(item.id ?? UUID())
                            )
                            .onTapGesture {
                                toggleSelection(item)
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, selectedIDs.isEmpty ? 0 : 100)
                }

                // Bottom bar: selected count + confirm button
                if !selectedIDs.isEmpty {
                    bottomBar
                }
            }
            .navigationTitle("创建我的穿搭")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .alert("最多选择 \(maxSelectionCount) 件", isPresented: $showMaxItemsAlert) {
                Button("好的") {}
            } message: {
                Text("AI 图片处理每次最多接受 \(maxSelectionCount) 张图片")
            }
            .alert("请先配置 API Key", isPresented: $showNoAPIKeyAlert) {
                Button("好的") {}
            } message: {
                Text("请先在「设置」页面填写阿里云 DashScope API Key，再使用 AI 功能")
            }
        }
        // sheet 放在 NavigationStack 外面，避免嵌套冲突
        .sheet(item: $createdOutfit) { outfit in
            TryOnView(outfit: outfit)
                .environmentObject(outfitVM)
        }
    }

    // MARK: - Category filter

    private var categoryFilter: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    let cats = ["全部"] + ClothingCategory.allCases.map { $0.rawValue }
                    ForEach(cats, id: \.self) { cat in
                        Button {
                            filterCategory = cat
                        } label: {
                            Text(cat)
                                .font(.subheadline)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(filterCategory == cat ? AppColors.accent : Color(.systemGray6))
                                .foregroundColor(filterCategory == cat ? .white : .primary)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Color(.systemBackground))
            Divider()
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 16) {
                // Selected preview strip
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(selectedItems) { item in
                            LocalImageView(path: item.flatLayImagePath ?? item.originalImagePath)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(AppColors.accent, lineWidth: 1.5)
                                )
                        }
                    }
                }

                VStack(alignment: .trailing, spacing: 4) {
                    Button {
                        confirmSelection()
                    } label: {
                        Text("完成 (\(selectedIDs.count)/\(maxSelectionCount))")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(AppColors.accent)
                            .clipShape(Capsule())
                    }
                    .disabled(selectedIDs.count < 1)
                    // 始终占位，避免按钮高度跳动
                    Text("已达上限")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .opacity(selectedIDs.count == maxSelectionCount ? 1 : 0)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
        }
    }

    // MARK: - Actions

    private func toggleSelection(_ item: ClothingItem) {
        guard let id = item.id else { return }
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            guard selectedIDs.count < maxSelectionCount else {
                showMaxItemsAlert = true
                return
            }
            selectedIDs.insert(id)
        }
    }

    private func confirmSelection() {
        guard !selectedItems.isEmpty else { return }
        guard !(KeychainHelper.load(for: KeychainKey.dashscopeAPIKey) ?? "").isEmpty else {
            showNoAPIKeyAlert = true
            return
        }
        // 按类别排序：上装→外套→下装→鞋子→其他
        let order: [String: Int] = ["上装": 0, "连衣裙": 0, "外套": 1, "下装": 2, "鞋子": 3, "包包": 4, "配饰": 5]
        let sorted = selectedItems.sorted {
            (order[$0.category ?? ""] ?? 6) < (order[$1.category ?? ""] ?? 6)
        }
        // 构造 OutfitSuggestion，score=1 表示用户手动选择
        createdOutfit = OutfitSuggestion(items: sorted, score: 1.0)
    }
}

// MARK: - Item selection cell

struct ItemSelectCell: View {
    let item: ClothingItem
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            LocalImageView(path: item.flatLayImagePath ?? item.originalImagePath)
                .aspectRatio(1, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? AppColors.accent : Color.clear, lineWidth: 2.5)
                )
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(AppColors.accent)
                            .background(Circle().fill(Color.white).padding(2))
                            .padding(5)
                    }
                }

            Text(item.subCategory ?? item.category ?? "")
                .font(.caption2)
                .lineLimit(1)
                .foregroundColor(isSelected ? AppColors.accent : .secondary)
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
