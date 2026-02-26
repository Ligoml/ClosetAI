import SwiftUI
import PhotosUI

struct TryOnView: View {
    let outfit: OutfitSuggestion
    @EnvironmentObject var outfitVM: OutfitViewModel
    @Environment(\.dismiss) var dismiss

    @State private var personImage: UIImage?
    @State private var showPhotoPicker = false
    @State private var collageImage: UIImage?
    @State private var isGeneratingCollage = false
    @State private var sliderPosition: CGFloat = 0.5
    @State private var showSaveDialog = false
    @State private var outfitName = ""
    @State private var activeTab = 0 // 0: collage, 1: try-on

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Tab selector
                    Picker("展示方式", selection: $activeTab) {
                        Text("拼接效果图").tag(0)
                        Text("虚拟试穿").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)

                    if activeTab == 0 {
                        collageSection
                    } else {
                        tryOnSection
                    }

                    // Items in this outfit
                    outfitItemsSection

                    Spacer(minLength: 20)
                }
            }
            .navigationTitle("穿搭效果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { showSaveDialog = true }
                        .foregroundColor(AppColors.accent)
                }
            }
            .alert("保存穿搭", isPresented: $showSaveDialog) {
                TextField("穿搭名称", text: $outfitName)
                Button("保存") {
                    saveOutfit()
                }
                Button("取消", role: .cancel) {}
            }
            .onAppear {
                // 自动加载设置中保存的模特图
                if personImage == nil, let filename = UserDefaults.standard.string(forKey: "closetai.modelPhotoFilename") {
                    personImage = ImageProcessingService.shared.loadImage(from: filename)
                }
            }
        }
        // sheet 放在 NavigationView 外面，避免嵌套问题
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerView(images: Binding(
                get: { personImage.map { [$0] } ?? [] },
                set: { personImage = $0.first }
            ))
        }
    }

    // MARK: - Collage Section

    private var collageSection: some View {
        VStack(spacing: 12) {
            if let collage = collageImage {
                // 已生成：展示图片
                Image(uiImage: collage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)

                HStack(spacing: 12) {
                    Button {
                        UIImageWriteToSavedPhotosAlbum(collage, nil, nil, nil)
                    } label: {
                        Label("保存到相册", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(AppColors.accent)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    Button {
                        collageImage = nil
                        generateCollage()
                    } label: {
                        Label("重新生成", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.systemGray5))
                            .foregroundColor(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal, 16)

            } else if isGeneratingCollage {
                // 生成中：loading
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .overlay(
                        VStack(spacing: 12) {
                            ProgressView().scaleEffect(1.2)
                            Text("AI 正在生成穿搭平铺图...")
                                .foregroundColor(.secondary)
                            Text("约 8-10 秒，请稍候")
                                .font(.caption)
                                .foregroundColor(Color(.systemGray3))
                        }
                    )
                    .padding(.horizontal, 16)
            } else {
                // 未生成：确认按钮
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .overlay(
                        VStack(spacing: 16) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 40))
                                .foregroundColor(Color(.systemGray3))
                            Text("点击下方按钮生成穿搭平铺图")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    )
                    .padding(.horizontal, 16)

                Button {
                    generateCollage()
                } label: {
                    Label("生成穿搭平铺图", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppColors.accent)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Try-On Section

    private var tryOnSection: some View {
        VStack(spacing: 16) {
            if outfitVM.isTryingOn {
                // Loading state with animated hanger
                VStack(spacing: 20) {
                    hangerAnimation
                    Text("AI 正在为您试穿...")
                        .foregroundColor(.secondary)
                    Text("约 8-10 秒，请稍候")
                        .font(.caption)
                        .foregroundColor(Color(.systemGray3))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
            } else if let tryOnResult = outfitVM.tryOnResultImage,
                      let personImg = personImage {
                // Split view comparison
                ComparisonSlider(beforeImage: personImg, afterImage: tryOnResult)
                    .frame(maxWidth: .infinity)
                    .frame(height: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)

                Button {
                    UIImageWriteToSavedPhotosAlbum(tryOnResult, nil, nil, nil)
                } label: {
                    Label("保存试穿结果", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppColors.accent)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal, 16)
            } else if let person = personImage {
                // 已有模特图：显示缩略预览，等待点击生成
                VStack(spacing: 12) {
                    Image(uiImage: person)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("更换模特图", systemImage: "arrow.triangle.2.circlepath")
                            .font(.subheadline)
                            .foregroundColor(AppColors.accent)
                    }
                }
                .padding(.vertical, 8)
            } else {
                // 无模特图：引导上传
                VStack(spacing: 16) {
                    Image(systemName: "person.crop.rectangle.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(Color(.systemGray3))
                    Text("上传模特正面照片")
                        .font(.headline)
                    Text("AI 将为模特虚拟试穿这套搭配\n也可在「设置」中保存常用模特图")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .font(.subheadline)
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("选择照片", systemImage: "photo")
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                            .background(AppColors.accent)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.vertical, 40)
            }

            if let _ = personImage, !outfitVM.isTryingOn, outfitVM.tryOnResultImage == nil {
                Button {
                    guard let person = personImage else { return }
                    Task {
                        await outfitVM.performVirtualTryOn(personImage: person, items: outfit.items)
                    }
                } label: {
                    Label("开始虚拟试穿", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppColors.accent)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal, 16)
            }

            if let error = outfitVM.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal, 16)
            }
        }
        .onChange(of: personImage) { _ in
            outfitVM.tryOnResultImage = nil
        }
    }

    // MARK: - Outfit Items Section

    private var outfitItemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本套包含 \(outfit.items.count) 件")
                .font(.headline)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(outfit.items) { item in
                        VStack(spacing: 6) {
                            LocalImageView(path: item.flatLayImagePath ?? item.originalImagePath)
                                .frame(width: 90, height: 90)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            Text(item.subCategory ?? item.category ?? "")
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Hanger Animation

    @State private var hangerAngle: Double = 0

    private var hangerAnimation: some View {
        Image(systemName: "tshirt.fill")
            .font(.system(size: 48))
            .foregroundColor(AppColors.accent.opacity(0.6))
            .rotationEffect(.degrees(hangerAngle))
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    hangerAngle = 10
                }
            }
    }

    // MARK: - Actions

    private func generateCollage() {
        isGeneratingCollage = true
        Task {
            collageImage = await outfitVM.generateCollage(for: outfit)
            isGeneratingCollage = false
        }
    }

    private func saveOutfit() {
        let name = outfitName.isEmpty ? "穿搭 \(Date().formatted(date: .abbreviated, time: .omitted))" : outfitName

        if let collage = collageImage,
           let path = ImageProcessingService.shared.saveImageToDocuments(collage, filename: "\(outfit.id.uuidString)_collage.jpg") {
            outfitVM.saveOutfit(outfit, collagePath: path, name: name)
        }
        dismiss()
    }
}

// MARK: - Comparison Slider

struct ComparisonSlider: View {
    let beforeImage: UIImage
    let afterImage: UIImage

    @State private var sliderOffset: CGFloat = 0.5
    @GestureState private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // After image (full)
                Image(uiImage: afterImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                // Before image (clipped to left side)
                Image(uiImage: beforeImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .mask(
                        Rectangle()
                            .frame(width: geo.size.width * sliderOffset)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    )

                // Divider line
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2)
                    .offset(x: geo.size.width * sliderOffset - 1)

                // Handle
                Circle()
                    .fill(Color.white)
                    .frame(width: 36, height: 36)
                    .overlay(
                        HStack(spacing: 2) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 10, weight: .bold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(.gray)
                    )
                    .shadow(radius: 4)
                    .offset(x: geo.size.width * sliderOffset - 18)

                // Labels
                VStack {
                    HStack {
                        Text("原图")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Spacer()
                        Text("试穿")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(12)
                    Spacer()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let newOffset = value.location.x / geo.size.width
                        sliderOffset = max(0.05, min(0.95, newOffset))
                    }
            )
        }
    }
}
