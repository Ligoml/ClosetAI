import SwiftUI

struct OutfitView: View {
    @EnvironmentObject var outfitVM: OutfitViewModel
    @EnvironmentObject var wardrobeVM: WardrobeViewModel

    @State private var selectedOutfit: OutfitSuggestion?
    @State private var showManualOutfit = false
    @State private var showAllOccasion: String? = nil

    var body: some View {
        NavigationView {
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
            .navigationBarTitleDisplayMode(.large)
            .onAppear { outfitVM.loadSavedOutfits() }
        }
        // FAB overlay
        .overlay(alignment: .bottomTrailing) {
            fabButton
        }
        .sheet(item: $selectedOutfit) { outfit in
            TryOnView(outfit: outfit)
                .environmentObject(outfitVM)
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
                OccasionAllOutfitsSheet(
                    occasion: occasion,
                    outfits: outfitVM.outfits(for: occasion),
                    wardrobeItems: wardrobeVM.items,
                    onSelect: { selectedOutfit = $0 },
                    onDelete: { outfitVM.deleteOutfit($0) }
                )
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
                Text("\(occasion)  \(outfits.count)套")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                Button {
                    showAllOccasion = occasion
                } label: {
                    Text("查看全部")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Horizontal scroll of outfit cards
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(outfits) { outfit in
                        OutfitCollageCard(outfit: outfit)
                            .onTapGesture { openOutfit(outfit) }
                            .contextMenu {
                                Button(role: .destructive) {
                                    outfitVM.deleteOutfit(outfit)
                                } label: {
                                    Label("删除穿搭", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 60)
            Image(systemName: "rectangle.stack.person.crop")
                .font(.system(size: 60))
                .foregroundColor(Color(.systemGray4))
            Text("还没有保存的搭配")
                .font(.title2)
                .fontWeight(.medium)
            Text("点击右下角 + 创建你的第一套搭配")
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
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(AppColors.accent)
                .clipShape(Circle())
                .shadow(color: AppColors.accent.opacity(0.4), radius: 8, x: 0, y: 4)
        }
        .padding(.trailing, 24)
        .padding(.bottom, 32)
    }

    // MARK: - Open Outfit

    private func openOutfit(_ outfit: Outfit) {
        let idStrings = (outfit.itemIDs ?? "").split(separator: ",").map { String($0) }
        let items = wardrobeVM.items.filter { item in
            guard let id = item.id else { return false }
            return idStrings.contains(id.uuidString)
        }
        if !items.isEmpty {
            selectedOutfit = OutfitSuggestion(items: items, score: 1.0)
        }
    }
}

// MARK: - Outfit Collage Card (160×200)

struct OutfitCollageCard: View {
    let outfit: Outfit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LocalImageView(path: outfit.collagePath)
                .frame(width: 160, height: 160)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(outfit.name ?? "未命名")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)

            Text(outfit.occasion ?? "")
                .font(.system(size: 10))
                .foregroundColor(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(AppColors.accent.opacity(0.8))
                .clipShape(Capsule())
        }
        .frame(width: 160, height: 200)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 1)
    }
}

// MARK: - Occasion All Outfits Sheet (查看全部)

struct OccasionAllOutfitsSheet: View {
    let occasion: String
    let outfits: [Outfit]
    let wardrobeItems: [ClothingItem]
    let onSelect: (OutfitSuggestion) -> Void
    let onDelete: (Outfit) -> Void

    @Environment(\.dismiss) var dismiss

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(outfits) { outfit in
                        OutfitCollageCard(outfit: outfit)
                            .frame(maxWidth: .infinity)
                            .onTapGesture {
                                if let suggestion = makeOutfitSuggestion(from: outfit) {
                                    onSelect(suggestion)
                                    dismiss()
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    onDelete(outfit)
                                } label: {
                                    Label("删除穿搭", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGray6).ignoresSafeArea())
            .navigationTitle("\(occasion) · \(outfits.count)套")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func makeOutfitSuggestion(from outfit: Outfit) -> OutfitSuggestion? {
        let idStrings = (outfit.itemIDs ?? "").split(separator: ",").map { String($0) }
        let items = wardrobeItems.filter { item in
            guard let id = item.id else { return false }
            return idStrings.contains(id.uuidString)
        }
        guard !items.isEmpty else { return nil }
        return OutfitSuggestion(items: items, score: 1.0)
    }
}
