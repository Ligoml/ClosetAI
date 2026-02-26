import SwiftUI

struct OutfitView: View {
    @EnvironmentObject var outfitVM: OutfitViewModel
    @EnvironmentObject var wardrobeVM: WardrobeViewModel
    @State private var selectedOutfit: OutfitSuggestion?
    @State private var showManualOutfit = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Occasion filter
                    occasionFilter

                    // Recommended outfits
                    if outfitVM.isGenerating {
                        generatingView
                    } else if outfitVM.recommendedOutfits.isEmpty {
                        emptyStateView
                    } else {
                        outfitList
                    }

                    // Saved outfits
                    if !outfitVM.savedOutfits.isEmpty {
                        savedOutfitsSection
                    }
                }
                .padding(.bottom, 20)
            }
            .navigationTitle("今日穿搭")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        // 手动创建穿搭
                        Button {
                            showManualOutfit = true
                        } label: {
                            Image(systemName: "plus")
                                .foregroundColor(AppColors.accent)
                        }
                        // 重新推荐
                        Button {
                            outfitVM.generateRecommendations(from: wardrobeVM.items)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(AppColors.accent)
                        }
                    }
                }
            }
            .onAppear {
                if outfitVM.recommendedOutfits.isEmpty {
                    outfitVM.generateRecommendations(from: wardrobeVM.items)
                }
            }
        }
        // sheet 放在 NavigationView 外面，避免嵌套问题
        .sheet(item: $selectedOutfit) { outfit in
            TryOnView(outfit: outfit)
                .environmentObject(outfitVM)
        }
        .sheet(isPresented: $showManualOutfit) {
            ManualOutfitView()
                .environmentObject(outfitVM)
                .environmentObject(wardrobeVM)
        }
    }

    // MARK: - Subviews

    private var occasionFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(outfitVM.occasions, id: \.self) { occasion in
                    Button(action: {
                        outfitVM.selectedOccasion = occasion
                        outfitVM.generateRecommendations(from: wardrobeVM.items)
                    }) {
                        Text(occasion)
                            .font(.subheadline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                outfitVM.selectedOccasion == occasion
                                    ? AppColors.accent
                                    : Color(.systemGray6)
                            )
                            .foregroundColor(
                                outfitVM.selectedOccasion == occasion ? .white : .primary
                            )
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private var generatingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.3)
            Text("AI 正在搭配...")
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 60)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 50))
                .foregroundColor(Color(.systemGray4))
            Text("衣橱衣物不足")
                .font(.title3)
            Text("至少需要 2 件衣物才能推荐穿搭")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 60)
        .padding(.horizontal, 32)
    }

    private var outfitList: some View {
        VStack(spacing: 16) {
            HStack {
                Text("为你推荐")
                    .font(.headline)
                Spacer()
                Text("\(outfitVM.recommendedOutfits.count) 套")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)

            ForEach(Array(outfitVM.recommendedOutfits.enumerated()), id: \.element.id) { index, outfit in
                OutfitCard(outfit: outfit, index: index + 1)
                    .onTapGesture {
                        selectedOutfit = outfit
                    }
            }
        }
    }

    private var savedOutfitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("已保存的穿搭")
                .font(.headline)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(outfitVM.savedOutfits) { outfit in
                        SavedOutfitCard(outfit: outfit)
                            .onTapGesture {
                                // 从 wardrobeVM 找回衣物，构造 OutfitSuggestion 进 TryOnView
                                let itemIDStrings = (outfit.itemIDs ?? "")
                                    .split(separator: ",")
                                    .map { String($0) }
                                let items = wardrobeVM.items.filter { item in
                                    guard let id = item.id else { return false }
                                    return itemIDStrings.contains(id.uuidString)
                                }
                                if !items.isEmpty {
                                    selectedOutfit = OutfitSuggestion(items: items, score: 1.0)
                                }
                            }
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
            }
        }
    }
}

// MARK: - Outfit Card

struct OutfitCard: View {
    let outfit: OutfitSuggestion
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("方案 \(index)", systemImage: "sparkles")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.accent)
                Spacer()
                Text(String(format: "匹配度 %.0f%%", outfit.score * 100))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Items preview strip
            HStack(spacing: 8) {
                ForEach(outfit.items) { item in
                    LocalImageView(path: item.flatLayImagePath ?? item.originalImagePath)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Spacer()
            }
            .frame(height: 80)

            // Item labels
            HStack(spacing: 8) {
                ForEach(outfit.items) { item in
                    Text(item.subCategory ?? item.category ?? "")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray6))
                        .clipShape(Capsule())
                }
                Spacer()
            }

            // Hint
            HStack {
                Spacer()
                Text("点击查看详情 & 试穿")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        .padding(.horizontal, 16)
    }
}

// MARK: - Saved Outfit Card

struct SavedOutfitCard: View {
    let outfit: Outfit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LocalImageView(path: outfit.collagePath)
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(outfit.name ?? "未命名穿搭")
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)

            Text(outfit.occasion ?? "")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(width: 140)
    }
}
