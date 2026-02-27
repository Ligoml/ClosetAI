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
    @State private var showSaveDialog = false
    @State private var outfitName = ""
    @State private var activeTab = 0 // 0: collage, 1: try-on

    // 预处理后的对比图（固定 3:4 尺寸，保证对齐）
    @State private var comparisonBefore: UIImage?
    @State private var comparisonAfter: UIImage?

    var body: some View {
        NavigationView {
            // ── Tab 选择器放在 ScrollView 外面，永远可见 ──
            VStack(spacing: 0) {
                tabSelector
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                Divider()

                ScrollView {
                    VStack(spacing: 24) {
                        if activeTab == 0 {
                            collageSection
                        } else {
                            tryOnSection
                        }

                        outfitItemsSection

                        Spacer(minLength: 20)
                    }
                    .padding(.top, 16)
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
                Button("保存") { saveOutfit() }
                Button("取消", role: .cancel) {}
            }
            .onAppear {
                if personImage == nil,
                   let filename = UserDefaults.standard.string(forKey: "closetai.modelPhotoFilename") {
                    personImage = ImageProcessingService.shared.loadImage(from: filename)
                }
            }
            // 试穿结果到来时，一次性归一化两张图
            .onChange(of: outfitVM.tryOnResultImage) { result in
                if let result = result, let person = personImage {
                    buildComparisonImages(person: person, result: result)
                }
            }
            // 切换模特图时清空旧对比图
            .onChange(of: personImage) { _ in
                outfitVM.tryOnResultImage = nil
                comparisonBefore = nil
                comparisonAfter = nil
            }
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerView(images: Binding(
                get: { personImage.map { [$0] } ?? [] },
                set: { personImage = $0.first }
            ))
        }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 0) {
            tabButton(title: "拼接效果图", index: 0)
            tabButton(title: "虚拟试穿",   index: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray4), lineWidth: 0.5))
    }

    private func tabButton(title: String, index: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                activeTab = index
            }
        } label: {
            Text(title)
                .font(.subheadline)
                .fontWeight(activeTab == index ? .semibold : .regular)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(activeTab == index ? AppColors.accent : Color(.systemGray6))
                .foregroundColor(activeTab == index ? .white : .primary)
        }
        .buttonStyle(.plain) // 防止 ScrollView 内 Button 的高亮延迟
    }

    // MARK: - Collage Section

    private var collageSection: some View {
        VStack(spacing: 12) {
            if let collage = collageImage {
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

                Button { generateCollage() } label: {
                    Label("生成穿搭平铺图", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppColors.accent)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Try-On Section

    private var tryOnSection: some View {
        VStack(spacing: 16) {
            if outfitVM.isTryingOn {
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

            } else if let before = comparisonBefore, let after = comparisonAfter {
                // 两张图已归一化，直接传入 ComparisonSlider
                ComparisonSlider(beforeImage: before, afterImage: after)
                    .frame(maxWidth: .infinity)
                    .frame(height: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)

                if let result = outfitVM.tryOnResultImage {
                    Button {
                        UIImageWriteToSavedPhotosAlbum(result, nil, nil, nil)
                    } label: {
                        Label("保存试穿结果", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(AppColors.accent)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                }

            } else if let person = personImage {
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
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 40)
            }

            if personImage != nil, !outfitVM.isTryingOn, outfitVM.tryOnResultImage == nil {
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
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            }

            if let error = outfitVM.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal, 16)
            }
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
        let name = outfitName.isEmpty
            ? "穿搭 \(Date().formatted(date: .abbreviated, time: .omitted))"
            : outfitName
        if let collage = collageImage,
           let path = ImageProcessingService.shared.saveImageToDocuments(
               collage, filename: "\(outfit.id.uuidString)_collage.jpg") {
            outfitVM.saveOutfit(outfit, collagePath: path, name: name)
        }
        dismiss()
    }

    /// 把两张图居中裁剪到相同的 3:4 固定尺寸，保证 ComparisonSlider 完全对齐
    private func buildComparisonImages(person: UIImage, result: UIImage) {
        let targetSize = CGSize(width: 480, height: 640) // 固定 3:4，与 frame(height:420) 匹配
        DispatchQueue.global(qos: .userInitiated).async {
            let before = centerCrop(person, to: targetSize)
            let after  = centerCrop(result,  to: targetSize)
            DispatchQueue.main.async {
                comparisonBefore = before
                comparisonAfter  = after
            }
        }
    }
}

// MARK: - Center Crop Helper (file-private)

private func centerCrop(_ image: UIImage, to targetSize: CGSize) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1.0
    let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
    return renderer.image { _ in
        let iw = image.size.width, ih = image.size.height
        let tw = targetSize.width,  th = targetSize.height
        let scale = max(tw / iw, th / ih)
        let drawW = iw * scale, drawH = ih * scale
        let drawRect = CGRect(x: (tw - drawW) / 2, y: (th - drawH) / 2,
                              width: drawW, height: drawH)
        image.draw(in: drawRect)
    }
}

// MARK: - Comparison Slider

struct ComparisonSlider: View {
    let beforeImage: UIImage  // 已经过 centerCrop，与 afterImage 同尺寸
    let afterImage: UIImage

    @State private var sliderOffset: CGFloat = 0.5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // After image（试穿结果，全显）
                Image(uiImage: afterImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                // Before image（原图，左侧裁剪显示）
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

                // 分割线
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2)
                    .offset(x: geo.size.width * sliderOffset - 1)

                // 拖拽手柄
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

                // 标签
                VStack {
                    HStack {
                        Text("原图")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundColor(.white).padding(6)
                            .background(Color.black.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Spacer()
                        Text("试穿")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundColor(.white).padding(6)
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
                        sliderOffset = max(0.05, min(0.95, value.location.x / geo.size.width))
                    }
            )
        }
    }
}
