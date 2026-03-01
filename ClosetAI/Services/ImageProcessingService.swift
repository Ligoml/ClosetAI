import Foundation
import UIKit
import CoreImage
import Vision

class ImageProcessingService {
    static let shared = ImageProcessingService()

    // MARK: - Preprocess Image

    func preprocessImage(_ image: UIImage) -> UIImage {
        // Normalize orientation first to prevent CIImage from stripping EXIF rotation
        let normalized = normalizeOrientation(image)
        guard let ciImage = CIImage(image: normalized) else { return normalized }
        let context = CIContext()

        // Auto-correct exposure and white balance
        var processed = ciImage
        if let autoAdjust = CIFilter(name: "CIAutoAdjust") {
            autoAdjust.setValue(processed, forKey: kCIInputImageKey)
            processed = autoAdjust.outputImage ?? processed
        }

        guard let cgImage = context.createCGImage(processed, from: processed.extent) else {
            return normalized
        }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }

    // MARK: - Remove Background (iOS 17+ / deployment target iOS 26)

    func removeBackground(from image: UIImage) async -> UIImage {
        return await removeBackgroundiOS17(from: image)
    }

    private func removeBackgroundiOS17(from image: UIImage) async -> UIImage {
        // Normalize orientation first so Vision sees the image right-side-up
        let normalized = normalizeOrientation(image)
        guard let cgImage = normalized.cgImage else { return image }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
            guard let result = request.results?.first else { return image }

            let maskPixelBuffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
            let maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)
            let originalCI = CIImage(cgImage: cgImage)

            // Apply mask: blend original with transparent background
            guard let blendFilter = CIFilter(name: "CIBlendWithMask") else { return image }
            blendFilter.setValue(originalCI, forKey: kCIInputImageKey)
            blendFilter.setValue(CIImage(color: .clear).cropped(to: originalCI.extent), forKey: kCIInputBackgroundImageKey)
            blendFilter.setValue(maskImage, forKey: kCIInputMaskImageKey)

            let context = CIContext()
            guard let outputCI = blendFilter.outputImage,
                  let outputCG = context.createCGImage(outputCI, from: outputCI.extent) else {
                return image
            }
            // Return with .up orientation (already normalized)
            return UIImage(cgImage: outputCG, scale: image.scale, orientation: .up)
        } catch {
            print("Background removal error: \(error)")
            return image
        }
    }

    /// Redraws the image so its CGImage is always in the correct upright orientation.
    private func normalizeOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return normalized
    }

    // MARK: - Generate Flat Lay Image (1024x1024)

    func generateFlatLayImage(from image: UIImage, backgroundColor: UIColor = .white) -> UIImage {
        let targetSize = CGSize(width: 1024, height: 1024)
        let renderer = UIGraphicsImageRenderer(size: targetSize)

        return renderer.image { ctx in
            // White background
            backgroundColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: targetSize))

            // Scale and center the clothing image
            let aspectRatio = image.size.width / image.size.height
            var drawRect: CGRect
            if aspectRatio > 1 {
                let height = targetSize.width / aspectRatio
                drawRect = CGRect(x: 0, y: (targetSize.height - height) / 2, width: targetSize.width, height: height)
            } else {
                let width = targetSize.height * aspectRatio
                drawRect = CGRect(x: (targetSize.width - width) / 2, y: 0, width: width, height: targetSize.height)
            }

            // Add subtle shadow
            ctx.cgContext.setShadow(offset: CGSize(width: 0, height: 4), blur: 12, color: UIColor.black.withAlphaComponent(0.15).cgColor)
            image.draw(in: drawRect)
        }
    }

    // MARK: - Quality Check

    func checkQuality(of image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 200 && height > 200 else { return false }

        // Check if image has foreground content (non-white pixels)
        guard let pixelData = cgImage.dataProvider?.data,
              let data = CFDataGetBytePtr(pixelData) else { return true }

        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow
        var nonWhiteCount = 0
        let totalPixels = width * height
        let sampleRate = max(1, totalPixels / 10000)

        var idx = 0
        for y in stride(from: 0, to: height, by: sampleRate) {
            for x in stride(from: 0, to: width, by: sampleRate) {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let r = data[offset]
                let g = data[offset + 1]
                let b = data[offset + 2]
                if r < 240 || g < 240 || b < 240 {
                    nonWhiteCount += 1
                }
                idx += 1
            }
        }

        let nonWhiteRatio = Double(nonWhiteCount) / Double(idx)
        return nonWhiteRatio > 0.05 // At least 5% non-white pixels
    }

    // MARK: - Generate Outfit Collage (1080x1080)

    func generateOutfitCollage(items: [(image: UIImage, category: String)]) -> UIImage {
        let targetSize = CGSize(width: 1080, height: 1080)
        let renderer = UIGraphicsImageRenderer(size: targetSize)

        return renderer.image { ctx in
            // Background
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: targetSize))

            let count = items.count
            guard count > 0 else { return }

            let layouts = collageLayout(for: count, canvasSize: targetSize)

            for (idx, item) in items.enumerated() {
                guard idx < layouts.count else { break }
                let rect = layouts[idx]

                // Shadow
                ctx.cgContext.setShadow(offset: CGSize(width: 0, height: 3), blur: 8,
                                        color: UIColor.black.withAlphaComponent(0.12).cgColor)

                // Draw item image
                item.image.draw(in: rect)
            }
        }
    }

    private func collageLayout(for count: Int, canvasSize: CGSize) -> [CGRect] {
        let padding: CGFloat = 32
        let spacing: CGFloat = 20
        let usable = CGSize(width: canvasSize.width - padding * 2,
                            height: canvasSize.height - padding * 2)

        switch count {
        case 1:
            return [CGRect(x: padding, y: padding, width: usable.width, height: usable.height)]

        case 2:
            // 上下布局：上衣在上（60%高度），下装在下（40%高度）
            let h1 = (usable.height - spacing) * 0.55
            let h2 = usable.height - spacing - h1
            return [
                CGRect(x: padding, y: padding, width: usable.width, height: h1),
                CGRect(x: padding, y: padding + h1 + spacing, width: usable.width, height: h2)
            ]

        case 3:
            // 上方一件大图（55%高），下方两件并排（45%高）
            let topH = (usable.height - spacing) * 0.55
            let botH = usable.height - spacing - topH
            let botW = (usable.width - spacing) / 2
            return [
                CGRect(x: padding, y: padding, width: usable.width, height: topH),
                CGRect(x: padding, y: padding + topH + spacing, width: botW, height: botH),
                CGRect(x: padding + botW + spacing, y: padding + topH + spacing, width: botW, height: botH)
            ]

        case 4:
            // 2x2 网格
            let w = (usable.width - spacing) / 2
            let h = (usable.height - spacing) / 2
            return [
                CGRect(x: padding, y: padding, width: w, height: h),
                CGRect(x: padding + w + spacing, y: padding, width: w, height: h),
                CGRect(x: padding, y: padding + h + spacing, width: w, height: h),
                CGRect(x: padding + w + spacing, y: padding + h + spacing, width: w, height: h)
            ]

        default:
            // Fallback: horizontal strip
            let w = (usable.width - spacing * CGFloat(count - 1)) / CGFloat(count)
            return (0..<count).map { i in
                CGRect(x: padding + CGFloat(i) * (w + spacing), y: padding, width: w, height: usable.height)
            }
        }
    }

    // MARK: - Save Image to Documents

    func saveImageToDocuments(_ image: UIImage, filename: String) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = docsURL.appendingPathComponent(filename)
        do {
            try data.write(to: fileURL)
            // 只存文件名，避免沙箱路径变化后失效
            return filename
        } catch {
            print("Save image error: \(error)")
            return nil
        }
    }

    func loadImage(from path: String) -> UIImage? {
        UIImage(contentsOfFile: LocalImageView.resolvePath(path))
    }
}
