//
//  UIImage.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 6/13/22.
//

import Photos
import UIKit

extension UIImage {
    /// Returns the most common quantized color in a small sample of the image.
    /// This preserves a cover's overall identity without exposing its artwork.
    func dominantColor(sampleSize: Int = 24) -> UIColor? {
        guard let cgImage, sampleSize > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = sampleSize * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: sampleSize * bytesPerRow)
        let rendered = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: sampleSize,
                height: sampleSize,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .low
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))
            return true
        }
        guard rendered else { return nil }

        struct Bucket {
            var count = 0
            var red = 0
            var green = 0
            var blue = 0
        }
        var buckets: [Int: Bucket] = [:]
        var chromaticBuckets: [Int: Bucket] = [:]
        var chromaticPixelCount = 0
        var sampledPixelCount = 0
        for offset in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            guard pixels[offset + 3] > 32 else { continue }
            let red = Int(pixels[offset])
            let green = Int(pixels[offset + 1])
            let blue = Int(pixels[offset + 2])
            sampledPixelCount += 1
            let key = (red >> 4) << 8 | (green >> 4) << 4 | (blue >> 4)
            var bucket = buckets[key, default: Bucket()]
            bucket.count += 1
            bucket.red += red
            bucket.green += green
            bucket.blue += blue
            buckets[key] = bucket

            let maximum = max(red, green, blue)
            let minimum = min(red, green, blue)
            let saturation = maximum == 0 ? 0 : Double(maximum - minimum) / Double(maximum)
            if saturation >= 0.12 {
                chromaticPixelCount += 1
                var chromaticBucket = chromaticBuckets[key, default: Bucket()]
                chromaticBucket.count += 1
                chromaticBucket.red += red
                chromaticBucket.green += green
                chromaticBucket.blue += blue
                chromaticBuckets[key] = chromaticBucket
            }
        }

        // Prefer an actual hue when color makes up most of the artwork. Fully
        // monochrome and genuinely grayscale covers still use their dominant gray.
        let imageIsPredominantlyChromatic = chromaticPixelCount * 5 >= sampledPixelCount * 2
        let candidateBuckets = imageIsPredominantlyChromatic ? chromaticBuckets : buckets
        guard let dominant = candidateBuckets.values.max(by: { $0.count < $1.count }), dominant.count > 0 else {
            return nil
        }
        return UIColor(
            red: CGFloat(dominant.red / dominant.count) / 255,
            green: CGFloat(dominant.green / dominant.count) / 255,
            blue: CGFloat(dominant.blue / dominant.count) / 255,
            alpha: 1
        )
    }

    @MainActor
    func saveToAlbum(_ name: String? = nil, viewController: UIViewController) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status != .restricted && status != .denied else {
            let alertController = confirmAction(
                title: NSLocalizedString("ENABLE_PERMISSION"),
                message: NSLocalizedString("PHOTOS_ACCESS_DENIED_TEXT"),
                continueActionName: NSLocalizedString("SETTINGS")
            ) {
                if let settings = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settings)
                }
            }
            viewController.present(alertController, animated: true)
            return
        }

        let albumName =
            name ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? "Aidoku"
        func fallback() {
            UIImageWriteToSavedPhotosAlbum(self, nil, nil, nil)
            LogManager.logger.error("Failed to save image to album: \(albumName)")
        }
        guard let album = fetchAlbum(albumName) else {
            fallback()
            return
        }

        PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest.creationRequestForAsset(from: self)
            guard
                let placeholder = request.placeholderForCreatedAsset,
                let albumChangeRequest = PHAssetCollectionChangeRequest(for: album)
            else {
                fallback()
                return
            }
            albumChangeRequest.addAssets([placeholder] as NSFastEnumeration)
        }
    }
}

@MainActor
private func confirmAction(
    title: String? = nil,
    message: String? = nil,
    actions: [UIAlertAction] = [],
    continueActionName: String = NSLocalizedString("CONTINUE"),
    destructive: Bool = true,
    proceed: @escaping () -> Void
) -> UIAlertController {
    let alertView = UIAlertController(
        title: title,
        message: message,
        preferredStyle: UIDevice.current.userInterfaceIdiom == .pad ? .alert : .actionSheet
    )

    for action in actions {
        alertView.addAction(action)
    }
    let action = UIAlertAction(
        title: continueActionName,
        style: destructive ? .destructive : .default
    ) { _ in
        proceed()
    }
    alertView.addAction(action)

    alertView.addAction(UIAlertAction(title: NSLocalizedString("CANCEL"), style: .cancel))

    return alertView
}

private func fetchAlbum(_ name: String) -> PHAssetCollection? {
    let options = PHFetchOptions()
    options.predicate = NSPredicate(format: "title == %@", name)
    if let album = PHAssetCollection.fetchAssetCollections(
        with: .album, subtype: .any, options: options
    ).firstObject {
        return album
    }

    var placeholder: PHObjectPlaceholder?
    do {
        try PHPhotoLibrary.shared().performChangesAndWait {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(
                withTitle: name)
            placeholder = request.placeholderForCreatedAssetCollection
        }
    } catch { return nil }
    guard let album = placeholder else { return nil }
    return PHAssetCollection.fetchAssetCollections(
        withLocalIdentifiers: [album.localIdentifier], options: nil
    ).firstObject
}
