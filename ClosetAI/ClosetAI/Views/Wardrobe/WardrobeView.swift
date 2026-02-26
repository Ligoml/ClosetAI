import SwiftUI

struct WardrobeView: View {
    @EnvironmentObject var viewModel: WardrobeViewModel
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedImage: UIImage?
    @State private var showAddMenu = false
    @State private var selectedItem: ClothingItem?
    @State private var showDeletedItems = false
    @State private var itemToRecord: ClothingItem?
    @State private var showRecordSuccess = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    // Category filter tabs
                    categoryTabs

                    // Search bar
                    searchBar

                    // Grid — always visible even while loading
                    if viewModel.filteredItems.isEmpty {
                        emptyStateView
                    } else {
                        clothingGrid
                    }
                }

                // Floating loading toast (doesn't block the list)
                if viewModel.isLoading {
                    loadingToast
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.isLoading)
                        .zIndex(10)
                }
            }
            .navigationTitle("我的衣橱")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    addButton
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    trashButton
                }
            }
            .onChange(of: selectedImage) { image in
                guard let image = image else { return }
                selectedImage = nil
                Task {
                    await viewModel.processAndAddItem(image: image)
                }
            }
            .alert("错误", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("确定") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            // 记录穿着确认弹窗
            .alert("记录穿着", isPresented: Binding(
                get: { itemToRecord != nil },
                set: { if !$0 { itemToRecord = nil } }
            )) {
                Button("确认") {
                    if let item = itemToRecord {
                        viewModel.recordWear(for: item)
                        showRecordSuccess = true
                    }
                    itemToRecord = nil
                }
                Button("取消", role: .cancel) { itemToRecord = nil }
            } message: {
                if let item = itemToRecord {
                    Text("将「\(item.subCategory ?? item.category ?? "此衣物")」今天的穿着记录下来？\n当前已穿 \(item.wearCount) 次")
                } else {
                    Text("")
                }
            }
            // 记录成功提示
            .alert("已记录", isPresented: $showRecordSuccess) {
                Button("好的") {}
            } message: {
                Text("穿着记录已更新，穿着次数 +1")
            }
        }
        // sheets 放在 NavigationView 外面，避免嵌套问题
        .sheet(isPresented: $showCamera) {
            CameraView(image: $selectedImage)
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerView(images: Binding(
                get: { selectedImage.map { [$0] } ?? [] },
                set: { selectedImage = $0.first }
            ))
        }
        .sheet(item: $selectedItem) { item in
            ClothingDetailView(item: item)
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showDeletedItems) {
            DeletedItemsView()
                .environmentObject(viewModel)
        }
    }

    // MARK: - Subviews

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.categories, id: \.self) { category in
                    Button(action: { viewModel.selectedCategory = category }) {
                        Text(category)
                            .font(.subheadline)
                            .fontWeight(viewModel.selectedCategory == category ? .semibold : .regular)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                viewModel.selectedCategory == category
                                    ? AppColors.accent
                                    : Color(.systemGray6)
                            )
                            .foregroundColor(
                                viewModel.selectedCategory == category ? .white : .primary
                            )
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("搜索颜色、风格、类别...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var clothingGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(viewModel.filteredItems) { item in
                    ClothingItemCard(item: item)
                        .onTapGesture { selectedItem = item }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                viewModel.softDelete(item)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button {
                                itemToRecord = item
                            } label: {
                                Label("记录穿着", systemImage: "checkmark.circle")
                            }
                            Button(role: .destructive) {
                                viewModel.softDelete(item)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .refreshable {
            viewModel.loadItems()
        }
    }

    private var loadingToast: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(0.9)
            Text("AI 正在处理服装...")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.78))
                .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
        )
        .padding(.bottom, 32)
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "tshirt")
                .font(.system(size: 60))
                .foregroundColor(Color(.systemGray4))
            Text("衣橱还是空的")
                .font(.title2)
                .fontWeight(.medium)
            Text("点击右上角 + 添加第一件衣物")
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private var addButton: some View {
        Menu {
            Button {
                showCamera = true
            } label: {
                Label("拍照", systemImage: "camera")
            }

            Button {
                showPhotoPicker = true
            } label: {
                Label("从相册选择", systemImage: "photo.on.rectangle")
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
                .foregroundColor(AppColors.accent)
        }
    }

    private var trashButton: some View {
        Button {
            showDeletedItems = true
        } label: {
            Image(systemName: "trash")
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Deleted Items View

struct DeletedItemsView: View {
    @EnvironmentObject var viewModel: WardrobeViewModel
    @Environment(\.dismiss) var dismiss

    var deletedItems: [ClothingItem] {
        PersistenceController.shared.fetchClothingItems(includeDeleted: true).filter { $0.isSoftDeleted }
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(deletedItems) { item in
                    HStack(spacing: 12) {
                        LocalImageView(path: item.flatLayImagePath ?? item.originalImagePath)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.subCategory ?? item.category ?? "未知")
                                .fontWeight(.medium)
                            Text(item.category ?? "")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button("恢复") {
                            viewModel.restore(item)
                        }
                        .foregroundColor(AppColors.accent)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            viewModel.permanentDelete(item)
                        } label: {
                            Label("永久删除", systemImage: "trash.fill")
                        }
                    }
                }
            }
            .navigationTitle("已删除")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
