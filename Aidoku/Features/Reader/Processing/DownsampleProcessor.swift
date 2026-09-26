//
//  DownsampleProcessor.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/17/22.
//

import Nuke
import UIKit

struct DownsampleProcessor: ImageProcessing {
    private let size: CGSize
    @MainActor
    let scaleFactor = UIScreen.main.scale

    @MainActor
    init(size: CGSize) {
        self.size = size
    }

    @MainActor
    init(width: CGFloat) {
        self.size = CGSize(width: width, height: CGFloat.infinity)
    }

    var identifier: String {
        "com.github.Aidoku/Aidoku/downsample?s=\(size)"
    }

    func process(_ image: PlatformImage) -> PlatformImage? {
        let scaleHor = size.width / image.size.width
        let scaleVert = size.height / image.size.height
        let scale = min(scaleHor, scaleVert)

        if scale == 1 {
            return image // no need to scale
        } else if scale > 1 {
            return image // don't want to upscale
        }

        let finalSize = CGSize(
            width: CGFloat(round(image.size.width * scale)),
            height: CGFloat(round(image.size.height * scale))
        )

        var data = image.pngData()
        if data == nil {
            data = image.jpegData(compressionQuality: 1)
            if data == nil {
                return nil
            }
        }

        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data! as CFData, imageSourceOptions) else {
            return nil
        }

        let maxDimension = round(max(finalSize.width, finalSize.height) * scaleFactor)
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as [CFString: Any] as CFDictionary

        guard let output = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options) else {
            return nil
        }

        return PlatformImage(cgImage: output, scale: scaleFactor, orientation: image.imageOrientation)
    }
}

/// Downsamples cover artwork so its shortest pixel dimension reaches the
/// requested size while preserving the source aspect ratio. The cover view
/// applies its own aspect-fill crop when it needs a fixed poster shape.
struct CoverDownsampleProcessor: ImageProcessing {
    private let shortestSide: CGFloat

    @MainActor
    init(shortestSide: CGFloat) {
        self.shortestSide = shortestSide
    }

    var identifier: String {
        "com.github.Aidoku/Aidoku/cover-downsample?shortestSide=\(shortestSide)"
    }

    func process(_ image: PlatformImage) -> PlatformImage? {
        guard let sourceImage = image.cgImage else { return image }
        let sourceWidth = CGFloat(sourceImage.width)
        let sourceHeight = CGFloat(sourceImage.height)
        let currentShortestSide = min(sourceWidth, sourceHeight)
        guard currentShortestSide > shortestSide else { return image }

        let scale = shortestSide / currentShortestSide
        let width = max(1, Int(round(sourceWidth * scale)))
        let height = max(1, Int(round(sourceHeight * scale)))
        let colorSpace = sourceImage.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpaceCreateDeviceRGB()
        let alphaInfo: CGImageAlphaInfo = switch sourceImage.alphaInfo {
            case .none, .noneSkipFirst, .noneSkipLast: .noneSkipLast
            default: .premultipliedLast
        }
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: alphaInfo.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let output = context.makeImage() else {
            return nil
        }

        return PlatformImage(cgImage: output, scale: 1, orientation: image.imageOrientation)
    }
}

/// Finished covers live separately from the original network image data so
/// scrolling through a large library cannot evict downloaded originals.
enum CoverProcessedDataCache {
    static let shared: DataCache? = {
        let cache = try? DataCache(name: "app.aidoku.Aidoku.processedcovers")
        cache?.sizeLimit = 300 * 1024 * 1024
        return cache
    }()
}

actor CoverProcessedCacheWriter {
    static let shared = CoverProcessedCacheWriter()

    func store(_ container: ImageContainer, for request: ImageRequest) {
        guard
            container.type != .gif,
            !container.isPreview,
            !ImagePipeline.shared.cache.containsData(for: request)
        else { return }
        ImagePipeline.shared.cache.storeCachedImage(container, for: request, caches: [.disk])
    }
}
