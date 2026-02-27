import SwiftUI

struct ClothingDetailView: View {
    let item: ClothingItem
    @EnvironmentObject var viewModel: WardrobeViewModel
    @EnvironmentObject var outfitVM: OutfitViewModel
    @Environment(\.dismiss) var dismiss

    @State private var showOriginal = false
    @State private var isEditing = false
    @State private var editedTags: ClothingTags
    @State private var showRecordConfirm = false
    @State private var showRecordSuccess = false
    @State private var selectedRelatedOutfit: Outfit?
    @State private var showAllRelatedOutfits = false

    init(item: ClothingItem) {
        self.item = item
        var tags = ClothingTags()
        tags.category = item.category ?? ""
        tags.subCategory = item.subCategory ?? ""
        tags.colors = (item.colors as? [String]) ?? []
        tags.pattern = item.pattern ?? ""
        tags.styles = (item.styles as? [String]) ?? []
        tags.seasons = (item.seasons as? [String]) ?? []
        tags.occasions = (item.occasions as? [String]) ?? []
        tags.notes = item.notes ?? ""
        _editedTags = State(initialValue: tags)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    imageSection
                    statsSection
                    tagsSection

                    // Related outfits (v2.0 new feature)
                    relatedOutfitsSection

                    if !editedTags.notes.isEmpty && !isEditing {
                        notesSection
                    }
                }
            }
            .navigationTitle(item.subCategory ?? item.category ?? "服装详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "保存" : "编辑") {
                        if isEditing { viewModel.updateItem(item, tags: editedTags) }
                        isEditing.toggle()
                    }
                    .foregroundColor(AppColors.accent)
                }
            }
        }
        .sheet(item: $selectedRelatedOutfit) { outfit in
            OutfitDetailView(outfit: outfit)
                .environmentObject(outfitVM)
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showAllRelatedOutfits) {
            AllRelatedOutfitsSheet(relatedOutfits: viewModel.outfits(containing: item))
                .environmentObject(outfitVM)
                .environmentObject(viewModel)
        }
    }

    // MARK: - Image Section

    private var imageSection: some View {
        VStack {
            ZStack {
                if showOriginal {
                    LocalImageView(path: item.originalImagePath, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(height: 320)
                        .background(Color(.systemGray6))
                        .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing)))
                } else {
                    LocalImageView(path: item.flatLayImagePath, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(height: 320)
                        .background(Color(.systemGray6))
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showOriginal)
            .gesture(DragGesture().onEnded { value in
                if abs(value.translation.width) > 50 {
                    withAnimation { showOriginal.toggle() }
                }
            })

            HStack(spacing: 8) {
                Circle()
                    .fill(showOriginal ? Color(.systemGray4) : AppColors.accent)
                    .frame(width: 6, height: 6)
                Circle()
                    .fill(showOriginal ? AppColors.accent : Color(.systemGray4))
                    .frame(width: 6, height: 6)
            }
            .padding(.top, 8)

            Text(showOriginal ? "原始照片" : "平铺图 (左右滑动切换)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                statItem(value: "\(item.wearCount)", label: "穿着次数")
                Divider().frame(height: 40)
                statItem(value: item.lastWornDate.map { formatDate($0) } ?? "从未", label: "上次穿着")
                Divider().frame(height: 40)
                statItem(value: formatDate(item.createdAt ?? Date()), label: "入橱时间")
            }

            Button {
                showRecordConfirm = true
            } label: {
                Label("记录今天穿了这件", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(AppColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .alert("记录穿着", isPresented: $showRecordConfirm) {
            Button("确认记录") {
                viewModel.recordWear(for: item)
                showRecordSuccess = true
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将今天的穿着记录下来？\n当前已穿 \(item.wearCount) 次")
        }
        .alert("记录成功", isPresented: $showRecordSuccess) {
            Button("好的") {}
        } message: {
            Text("穿着记录已更新 ✓")
        }
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.headline).fontWeight(.semibold)
            Text(label).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tags Section

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("标签信息")
                .font(.headline)
                .padding(.horizontal, 16)

            if isEditing {
                editableTagsForm
            } else {
                readonlyTags
            }
        }
    }

    private var readonlyTags: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !editedTags.category.isEmpty { tagRow(label: "大类", value: editedTags.category) }
            if !editedTags.subCategory.isEmpty { tagRow(label: "小类", value: editedTags.subCategory) }
            if !editedTags.colors.isEmpty { tagRow(label: "颜色", tags: editedTags.colors) }
            if !editedTags.pattern.isEmpty { tagRow(label: "图案", value: editedTags.pattern) }
            if !editedTags.styles.isEmpty { tagRow(label: "风格", tags: editedTags.styles) }
            if !editedTags.seasons.isEmpty { tagRow(label: "季节", tags: editedTags.seasons) }
            if !editedTags.occasions.isEmpty { tagRow(label: "场合", tags: editedTags.occasions) }
        }
        .padding(.horizontal, 16)
    }

    private func tagRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 48, alignment: .leading)
            Text(value).font(.subheadline)
        }
    }

    private func tagRow(label: String, tags: [String]) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 48, alignment: .leading)
            TagView(tags: tags)
        }
    }

    private var editableTagsForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            editField(label: "大类", text: $editedTags.category)
            editField(label: "小类", text: $editedTags.subCategory)
            editField(label: "图案", text: $editedTags.pattern)
            editField(label: "备注", text: $editedTags.notes)
            multiSelectRow(label: "季节", selected: $editedTags.seasons, options: Season.allCases.map { $0.rawValue })
            multiSelectRow(label: "场合", selected: $editedTags.occasions, options: Occasion.allCases.map { $0.rawValue })
        }
        .padding(.horizontal, 16)
    }

    private func editField(label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundColor(.secondary)
            TextField(label, text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func multiSelectRow(label: String, selected: Binding<[String]>, options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption).foregroundColor(.secondary)
            FlowLayout(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    let isSelected = selected.wrappedValue.contains(option)
                    Button(action: {
                        if isSelected {
                            selected.wrappedValue.removeAll { $0 == option }
                        } else {
                            selected.wrappedValue.append(option)
                        }
                    }) {
                        Text(option)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(isSelected ? AppColors.accent : Color(.systemGray5))
                            .foregroundColor(isSelected ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Related Outfits Section (v2.0)

    private var relatedOutfitsSection: some View {
        let related = viewModel.outfits(containing: item)
        return VStack(alignment: .leading, spacing: 12) {
            Text("出现在哪些搭配中")
                .font(.headline)
                .padding(.horizontal, 16)

            if related.isEmpty {
                HStack(spacing: 4) {
                    Text("这件还没有搭配方案，去穿搭 Tab 新建一套吧")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(related.prefix(5)) { outfit in
                            RelatedOutfitCard(outfit: outfit)
                                .onTapGesture { selectedRelatedOutfit = outfit }
                        }

                        if related.count > 5 {
                            Button {
                                showAllRelatedOutfits = true
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.system(size: 32))
                                        .foregroundColor(.secondary)
                                    Text("查看全部\n\(related.count)套")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(width: 80, height: 150)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("备注").font(.headline)
            Text(editedTags.notes).font(.body).foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }
}

// MARK: - All Related Outfits Sheet

struct AllRelatedOutfitsSheet: View {
    let relatedOutfits: [Outfit]
    @EnvironmentObject var outfitVM: OutfitViewModel
    @EnvironmentObject var wardrobeVM: WardrobeViewModel

    @Environment(\.dismiss) var dismiss
    @State private var selectedOutfit: Outfit?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(relatedOutfits) { outfit in
                        OutfitCollageCard(outfit: outfit)
                            .frame(maxWidth: .infinity)
                            .onTapGesture { selectedOutfit = outfit }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGray6).ignoresSafeArea())
            .navigationTitle("相关搭配（\(relatedOutfits.count)套）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .sheet(item: $selectedOutfit) { outfit in
            OutfitDetailView(outfit: outfit)
                .environmentObject(outfitVM)
                .environmentObject(wardrobeVM)
        }
    }
}

// MARK: - Related Outfit Card

struct RelatedOutfitCard: View {
    let outfit: Outfit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LocalImageView(path: outfit.collagePath)
                .frame(width: 100, height: 120)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 1)

            Text(outfit.name ?? "未命名")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)

            Text(outfit.occasion ?? "")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(.systemGray6))
                .clipShape(Capsule())
        }
        .frame(width: 100)
    }
}
