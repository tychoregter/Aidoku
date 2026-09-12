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
        let finalMaxDimension = round(max(sourceWidth, sourceHeight) * scale)

        guard let data = image.pngData() ?? image.jpegData(compressionQuality: 1),
              let imageSource = CGImageSourceCreateWithData(data as CFData, [
                  kCGImageSourceShouldCache: false
              ] as CFDictionary) else {
            return nil
        }

        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: finalMaxDimension
        ] as [CFString: Any] as CFDictionary

        guard let output = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options) else {
            return nil
        }

        return PlatformImage(cgImage: output, scale: 1, orientation: image.imageOrientation)
    }
}
