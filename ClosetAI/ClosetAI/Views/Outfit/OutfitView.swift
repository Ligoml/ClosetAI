import SwiftUI

struct OutfitView: View {
    @EnvironmentObject var outfitVM: OutfitViewModel
    @EnvironmentObject var wardrobeVM: WardrobeViewModel

    @State private var selectedOutfit: Outfit?
    @State private var showManualOutfit = false
    @State private var showAllOccasion: String? = nil
    @State private var outfitToDelete: Outfit? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGray6).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 12) {
                        if outfitVM.savedOutfits.isEmpty {
                            emptyStateView
                        } else {
                            outfitSections
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
            }
            .navigationTitle("穿搭")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { outfitVM.loadSavedOutfits() }
            .alert("确认删除？", isPresented: Binding(
                get: { outfitToDelete != nil },
                set: { if !$0 { outfitToDelete = nil } }
            )) {
                Button("删除穿搭", role: .destructive) {
                    if let outfit = outfitToDelete { outfitVM.deleteOutfit(outfit) }
                    outfitToDelete = nil
                }
                Button("取消", role: .cancel) { outfitToDelete = nil }
            } message: {
                Text("删除后无法恢复")
            }
        }
        // FAB overlay
        .overlay(alignment: .bottomTrailing) {
            fabButton
        }
        .sheet(item: $selectedOutfit) { outfit in
            OutfitDetailView(outfit: outfit)
                .environmentObject(outfitVM)
                .environmentObject(wardrobeVM)
        }
        .sheet(isPresented: $showManualOutfit) {
            ManualOutfitView()
                .environmentObject(outfitVM)
                .environmentObject(wardrobeVM)
        }
        .sheet(isPresented: Binding(
            get: { showAllOccasion != nil },
            set: { if !$0 { showAllOccasion = nil } }
        )) {
            if let occasion = showAllOccasion {
                OccasionAllOutfitsSheet(occasion: occasion)
                    .environmentObject(outfitVM)
                    .environmentObject(wardrobeVM)
            }
        }
    }

    // MARK: - Occasion Sections

    private var outfitSections: some View {
        ForEach(outfitVM.occupiedOccasions, id: \.self) { occasion in
            let outfits = outfitVM.outfits(for: occasion)
            outfitSectionCard(occasion: occasion, outfits: outfits)
        }
    }

    private func outfitSectionCard(occasion: String, outfits: [Outfit]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack {
                HStack(spacing: 5) {
                    Text(occasion)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("\(outfits.count)")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    showAllOccasion = occasion
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Horizontal scroll of outfit cards
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(outfits) { outfit in
                        OutfitCollageCard(outfit: outfit)
                            .onTapGesture { selectedOutfit = outfit }
                            .contextMenu {
                                Button(role: .destructive) {
                                    outfitToDelete = outfit
                                } label: {
                                    Label("删除穿搭", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 60)
            Image(systemName: "wand.and.stars")
                .font(.system(size: 52))
                .foregroundColor(Color(.systemGray4))
            Text("还没有保存的搭配")
                .font(.title3)
                .fontWeight(.medium)
            Text("点击右下角 + 创建你的第一套搭配")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 60)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - FAB

    private var fabButton: some View {
        Button { showManualOutfit = true } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(AppColors.accent)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 3)
        }
        .padding(.trailing, 24)
        .padding(.bottom, 32)
    }
}

// MARK: - Outfit Collage Card (140×160, image-only)

struct OutfitCollageCard: View {
    let outfit: Outfit

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LocalImageView(path: outfit.collagePath)
                .frame(width: 140, height: 160)
                .clipped()

            if let name = outfit.name, !name.isEmpty {
                Text(name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.35))
                    .padding(6)
            }
        }
        .frame(width: 140, height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 1)
    }
}

// MARK: - Occasion All Outfits Sheet (查看全部)

struct OccasionAllOutfitsSheet: View {
    let occasion: String
    @EnvironmentObject var outfitVM: OutfitViewModel
    @EnvironmentObject var wardrobeVM: WardrobeViewModel

    @Environment(\.dismiss) var dismiss
    @State private var selectedOutfit: Outfit?
    @State private var outfitToDelete: Outfit? = nil

    private var outfits: [Outfit] { outfitVM.outfits(for: occasion) }
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if outfits.isEmpty {
                    VStack(spacing: 16) {
                        Spacer(minLength: 60)
                        Image(systemName: "tray")
                            .font(.system(size: 40))
                            .foregroundColor(Color(.systemGray4))
                        Text("此分类暂无搭配")
                            .foregroundColor(.secondary)
                        Spacer(minLength: 60)
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(outfits) { outfit in
                            OutfitCollageCard(outfit: outfit)
                                .frame(maxWidth: .infinity)
                                .onTapGesture { selectedOutfit = outfit }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        outfitToDelete = outfit
                                    } label: {
                                        Label("删除穿搭", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(16)
                }
            }
            .background(Color(.systemGray6).ignoresSafeArea())
            .navigationTitle("\(occasion) · \(outfits.count)套")
            .navigationBarTitleDisplayMode(.inline)
            .alert("确认删除？", isPresented: Binding(
                get: { outfitToDelete != nil },
                set: { if !$0 { outfitToDelete = nil } }
            )) {
                Button("删除穿搭", role: .destructive) {
                    if let outfit = outfitToDelete { outfitVM.deleteOutfit(outfit) }
                    outfitToDelete = nil
                }
                Button("取消", role: .cancel) { outfitToDelete = nil }
            } message: {
                Text("删除后无法恢复")
            }
        }
        .sheet(item: $selectedOutfit) { outfit in
            OutfitDetailView(outfit: outfit)
                .environmentObject(outfitVM)
                .environmentObject(wardrobeVM)
        }
    }
}

// MARK: - Outfit Detail View (v2.0)

struct OutfitDetailView: View {
    let outfit: Outfit
    @EnvironmentObject var outfitVM: OutfitViewModel
    @EnvironmentObject var wardrobeVM: WardrobeViewModel
    @Environment(\.dismiss) var dismiss

    @State private var showTryOn = false
    @State private var showEditSheet = false
    @State private var showDeleteConfirm = false
    @State private var selectedItem: ClothingItem?

    private var outfitItems: [ClothingItem] {
        let idStrings = (outfit.itemIDs ?? "").split(separator: ",").map { String($0) }
        return wardrobeVM.items.filter { item in
            guard let id = item.id else { return false }
            return idStrings.contains(id.uuidString)
        }
    }

    private var outfitSuggestion: OutfitSuggestion {
        OutfitSuggestion(items: outfitItems, score: 1.0)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        collagSection
                        if outfit.tryOnResultPath != nil {
                            tryOnResultSection
                        }
                        itemsSection
                    }
                    .padding(.bottom, 16)
                }

                tryOnButton
            }
            .navigationTitle(outfit.name ?? "搭配详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showEditSheet = true
                        } label: {
                            Label("编辑名称/场合", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("删除穿搭", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(AppColors.accent)
                    }
                }
            }
            .alert("确认删除？", isPresented: $showDeleteConfirm) {
                Button("删除穿搭", role: .destructive) {
                    outfitVM.deleteOutfit(outfit)
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("删除后无法恢复")
            }
        }
        .sheet(isPresented: $showTryOn) {
            TryOnView(outfit: outfitSuggestion, savedOutfit: outfit)
                .environmentObject(outfitVM)
        }
        .sheet(isPresented: $showEditSheet) {
            EditOutfitSheet(outfit: outfit)
                .environmentObject(outfitVM)
        }
        .sheet(item: $selectedItem) { item in
            ClothingDetailView(item: item)
                .environmentObject(wardrobeVM)
                .environmentObject(outfitVM)
        }
    }

    // MARK: - Try-On Result Section

    private var tryOnResultSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("上次试穿效果")
                    .font(.headline)
                Spacer()
                Text("点击下方按钮重新生成")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)

            LocalImageView(path: outfit.tryOnResultPath, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 300)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
        }
    }

    // MARK: - Collage Section

    private var collagSection: some View {
        LocalImageView(path: outfit.collagePath, contentMode: .fit)
            .frame(maxWidth: .infinity, minHeight: 200)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    // MARK: - Items Section

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("包含 \(outfitItems.count) 件")
                    .font(.headline)
                    .padding(.horizontal, 16)

                if let occasion = outfit.occasion {
                    Text(occasion)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(AppColors.accent.opacity(0.85))
                        .clipShape(Capsule())
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(outfitItems) { item in
                        VStack(spacing: 6) {
                            LocalImageView(path: item.flatLayImagePath ?? item.originalImagePath)
                                .frame(width: 100, height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 1)

                            Text(item.subCategory ?? item.category ?? "")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .frame(width: 100)
                        }
                        .onTapGesture { selectedItem = item }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Try-On Button

    private var tryOnButton: some View {
        let hasResult = outfit.tryOnResultPath != nil
        return VStack(spacing: 0) {
            Divider()
            Button {
                showTryOn = true
            } label: {
                Label(
                    hasResult ? "重新试穿" : "虚拟试穿",
                    systemImage: hasResult ? "arrow.clockwise" : "person.crop.rectangle.badge.plus"
                )
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
        }
    }
}

// MARK: - Edit Outfit Sheet

struct EditOutfitSheet: View {
    let outfit: Outfit
    @EnvironmentObject var outfitVM: OutfitViewModel
    @Environment(\.dismiss) var dismiss

    @State private var name: String = ""
    @State private var occasion: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("搭配名称") {
                    TextField("名称（留空则自动命名）", text: $name)
                }
                Section("场合") {
                    Picker("场合", selection: $occasion) {
                        ForEach(outfitVM.occasions, id: \.self) { o in
                            Text(o).tag(o)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("编辑搭配")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        outfitVM.updateOutfit(outfit, name: name, occasion: occasion)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppColors.accent)
                    }
                }
            }
        }
        .onAppear {
            name = outfit.name ?? ""
            occasion = outfit.occasion ?? outfitVM.occasions.first ?? "日常"
        }
    }
}
