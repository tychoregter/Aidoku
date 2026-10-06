//
//  UIImage.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 6/13/22.
//

import Photos
import UIKit

private struct PerceptualColorKey: Hashable, Comparable {
    let lightness: Int
    let redGreen: Int
    let yellowBlue: Int

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.lightness != rhs.lightness { return lhs.lightness < rhs.lightness }
        if lhs.redGreen != rhs.redGreen { return lhs.redGreen < rhs.redGreen }
        return lhs.yellowBlue < rhs.yellowBlue
    }
}

private struct PerceptualColorBucket {
    var count = 0
    var red = 0.0
    var green = 0.0
    var blue = 0.0
    var lightness = 0.0
    var redGreen = 0.0
    var yellowBlue = 0.0

    mutating func add(red: Double, green: Double, blue: Double, lightness: Double, redGreen: Double, yellowBlue: Double) {
        count += 1
        self.red += red
        self.green += green
        self.blue += blue
        self.lightness += lightness
        self.redGreen += redGreen
        self.yellowBlue += yellowBlue
    }

    mutating func add(_ other: Self) {
        count += other.count
        red += other.red
        green += other.green
        blue += other.blue
        lightness += other.lightness
        redGreen += other.redGreen
        yellowBlue += other.yellowBlue
    }
}

private struct CoverColorSample {
    let red: Double
    let green: Double
    let blue: Double
    let lightness: Double
    let redGreen: Double
    let yellowBlue: Double
    let chroma: Double
    let saturation: Double
    let hue: Double

    var rgb: Int {
        let redByte = Int((red * 255).rounded())
        let greenByte = Int((green * 255).rounded())
        let blueByte = Int((blue * 255).rounded())
        return (redByte << 16) | (greenByte << 8) | blueByte
    }
}

extension UIImage {
    /// Ranks color families across a small cover sample, then returns an actual sampled color.
    /// Meaningful colored areas still take priority over neutral backgrounds.
    func dominantColor(sampleSize: Int = 96) -> UIColor? {
        dominantColorSample(sampleSize: sampleSize)?.color
    }

    /// The fingerprint is of the exact pixels used by the picker. It detects
    /// updated artwork even when a source keeps the same cover URL.
    func dominantColorSample(sampleSize: Int = 96) -> (color: UIColor, fingerprint: UInt64)? {
        guard let cgImage, sampleSize > 0 else { return nil }

        let scale = min(
            CGFloat(sampleSize) / CGFloat(cgImage.width),
            CGFloat(sampleSize) / CGFloat(cgImage.height)
        )
        let sampleWidth = max(1, Int((CGFloat(cgImage.width) * scale).rounded()))
        let sampleHeight = max(1, Int((CGFloat(cgImage.height) * scale).rounded()))
        let bytesPerPixel = 4
        let bytesPerRow = sampleWidth * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: sampleHeight * bytesPerRow)
        let rendered = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: sampleWidth,
                height: sampleHeight,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))
            return true
        }
        guard rendered else { return nil }

        let fingerprint = pixels.reduce(UInt64(14_695_981_039_346_656_037)) { hash, byte in
            (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }

        func linearComponent(_ component: Double) -> Double {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }

        func usesWhiteHeaderTextInLightMode(_ sample: CoverColorSample) -> Bool {
            // Light headers normally use 95% of the sampled RGB value. Covers
            // brightened by the dark-mode floor remain well below this cutoff.
            let red = linearComponent(sample.red * 0.95)
            let green = linearComponent(sample.green * 0.95)
            let blue = linearComponent(sample.blue * 0.95)
            return 0.2126 * red + 0.7152 * green + 0.0722 * blue <= 0.4
        }

        func whiteHeaderTextBonus(_ sample: CoverColorSample) -> Double {
            usesWhiteHeaderTextInLightMode(sample) ? 1.08 : 1
        }

        var buckets: [PerceptualColorKey: PerceptualColorBucket] = [:]
        var coloredSamples: [CoverColorSample] = []
        var sampledPixelCount = 0
        for offset in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            guard pixels[offset + 3] > 32 else { continue }
            let alpha = Double(pixels[offset + 3]) / 255
            let red = min(Double(pixels[offset]) / (255 * alpha), 1)
            let green = min(Double(pixels[offset + 1]) / (255 * alpha), 1)
            let blue = min(Double(pixels[offset + 2]) / (255 * alpha), 1)

            let linearRed = linearComponent(red)
            let linearGreen = linearComponent(green)
            let linearBlue = linearComponent(blue)
            let l = pow(0.4122214708 * linearRed + 0.5363325363 * linearGreen + 0.0514459929 * linearBlue, 1.0 / 3)
            let m = pow(0.2119034982 * linearRed + 0.6806995451 * linearGreen + 0.1073969566 * linearBlue, 1.0 / 3)
            let s = pow(0.0883024619 * linearRed + 0.2817188376 * linearGreen + 0.6299787005 * linearBlue, 1.0 / 3)
            let lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
            let redGreen = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
            let yellowBlue = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
            let key = PerceptualColorKey(
                lightness: Int(floor(lightness / 0.045)),
                redGreen: Int(floor(redGreen / 0.045)),
                yellowBlue: Int(floor(yellowBlue / 0.045))
            )

            sampledPixelCount += 1
            var bucket = buckets[key, default: PerceptualColorBucket()]
            bucket.add(red: red, green: green, blue: blue, lightness: lightness, redGreen: redGreen, yellowBlue: yellowBlue)
            buckets[key] = bucket

            let maximum = max(red, green, blue)
            let minimum = min(red, green, blue)
            let saturation = maximum == 0 ? 0 : (maximum - minimum) / maximum
            let chroma = hypot(redGreen, yellowBlue)
            // OKLab chroma keeps nearly black or gray pixels with noisy RGB ratios out.
            if saturation >= 0.18 && chroma >= 0.035 && maximum - minimum >= 12.0 / 255 {
                coloredSamples.append(CoverColorSample(
                    red: red,
                    green: green,
                    blue: blue,
                    lightness: lightness,
                    redGreen: redGreen,
                    yellowBlue: yellowBlue,
                    chroma: chroma,
                    saturation: saturation,
                    hue: atan2(yellowBlue, redGreen)
                ))
            }
        }

        // Group across lightness so bright and dark shades of the same hue compete together.
        if !coloredSamples.isEmpty && coloredSamples.count * 50 >= sampledPixelCount {
            let familyCount = 24
            let halfWidth = Double.pi / 8 // 22.5 degrees on either side of the center
            var bestFamily: [CoverColorSample] = []
            var bestFamilyScore = 0.0
            for index in 0..<familyCount {
                let center = -Double.pi + (Double(index) + 0.5) * 2 * Double.pi / Double(familyCount)
                let family = coloredSamples.filter { sample in
                    let distance = abs(sample.hue - center)
                    return min(distance, 2 * Double.pi - distance) <= halfWidth
                }
                guard !family.isEmpty else { continue }
                let averageChroma = family.reduce(0) { $0 + $1.chroma } / Double(family.count)
                let averageSaturation = family.reduce(0) { $0 + $1.saturation } / Double(family.count)
                let colorStrength = 0.45 + 1.75 * pow(min(averageChroma / 0.18, 1), 1.3)
                let saturationBias = 0.5 + 0.5 * sqrt(max(averageSaturation, 0))
                let whiteTextFraction = Double(family.filter(usesWhiteHeaderTextInLightMode).count)
                    / Double(family.count)
                let score = pow(Double(family.count), 0.84) * colorStrength * saturationBias
                    * (1 + 0.05 * whiteTextFraction)
                if score > bestFamilyScore {
                    bestFamily = family
                    bestFamilyScore = score
                }
            }

            if !bestFamily.isEmpty {
                func vibrancyBonus(_ sample: CoverColorSample) -> Double {
                    1 + 0.10 * min(sample.chroma / 0.18, 1)
                }
                func saturationBonus(_ sample: CoverColorSample) -> Double {
                    0.4 + 0.6 * sqrt(max(sample.saturation, 0))
                }
                func finalColorBonus(_ sample: CoverColorSample) -> Double {
                    vibrancyBonus(sample) * whiteHeaderTextBonus(sample) * saturationBonus(sample)
                }
                func distanceSquared(_ first: CoverColorSample, _ second: CoverColorSample) -> Double {
                    let lightness = first.lightness - second.lightness
                    let redGreen = first.redGreen - second.redGreen
                    let yellowBlue = first.yellowBlue - second.yellowBlue
                    return lightness * lightness + redGreen * redGreen + yellowBlue * yellowBlue
                }

                // Count nearby shades before choosing an exact RGB value, so a small
                // repeated highlight cannot beat a large patch of slightly varied pixels.
                let shadeRadiusSquared = 0.045 * 0.045
                var shadeCenter = bestFamily[0]
                var bestShadeScore = 0.0
                for sample in bestFamily {
                    let support = bestFamily.reduce(0) { count, neighbor in
                        count + (distanceSquared(sample, neighbor) <= shadeRadiusSquared ? 1 : 0)
                    }
                    let score = Double(support) * finalColorBonus(sample)
                    if score > bestShadeScore {
                        shadeCenter = sample
                        bestShadeScore = score
                    }
                }
                let shadeSamples = bestFamily.filter { distanceSquared($0, shadeCenter) <= shadeRadiusSquared }
                var frequencies: [Int: Int] = [:]
                for sample in shadeSamples { frequencies[sample.rgb, default: 0] += 1 }
                let mostFrequent = frequencies.values.max() ?? 0
                let representative = shadeSamples
                    .max { first, second in
                        let firstBonus = finalColorBonus(first)
                        let secondBonus = finalColorBonus(second)
                        let firstScore = mostFrequent == 1 ? 1 : Double(frequencies[first.rgb] ?? 0) * firstBonus
                        let secondScore = mostFrequent == 1 ? 1 : Double(frequencies[second.rgb] ?? 0) * secondBonus
                        if firstScore != secondScore { return firstScore < secondScore }
                        let firstDistance = distanceSquared(first, shadeCenter) / firstBonus
                        let secondDistance = distanceSquared(second, shadeCenter) / secondBonus
                        return firstDistance == secondDistance
                            ? first.rgb > second.rgb
                            : firstDistance > secondDistance
                    }
                if let representative {
                    return (UIColor(
                        red: CGFloat(representative.red),
                        green: CGFloat(representative.green),
                        blue: CGFloat(representative.blue),
                        alpha: 1
                    ), fingerprint)
                }
            }
        }

        // Covers that are almost entirely neutral still use the largest perceptual group.
        let orderedBuckets = buckets.sorted { $0.key < $1.key }.map { $0.value }
        var bestGroup = PerceptualColorBucket()
        var bestScore = 0.0
        let maximumDistanceSquared = 0.07 * 0.07

        for center in orderedBuckets {
            let centerLightness = center.lightness / Double(center.count)
            let centerRedGreen = center.redGreen / Double(center.count)
            let centerYellowBlue = center.yellowBlue / Double(center.count)
            var group = PerceptualColorBucket()
            for neighbor in orderedBuckets {
                let lightnessDifference = centerLightness - neighbor.lightness / Double(neighbor.count)
                let redGreenDifference = centerRedGreen - neighbor.redGreen / Double(neighbor.count)
                let yellowBlueDifference = centerYellowBlue - neighbor.yellowBlue / Double(neighbor.count)
                let distanceSquared = lightnessDifference * lightnessDifference
                    + redGreenDifference * redGreenDifference
                    + yellowBlueDifference * yellowBlueDifference
                if distanceSquared <= maximumDistanceSquared {
                    group.add(neighbor)
                }
            }
            let averageRed = group.red / Double(group.count)
            let averageGreen = group.green / Double(group.count)
            let averageBlue = group.blue / Double(group.count)
            let score = Double(group.count)
            if score > bestScore {
                bestGroup = group
                bestScore = score
            }
        }
        guard bestGroup.count > 0 else { return nil }
        return (UIColor(
            red: CGFloat(bestGroup.red / Double(bestGroup.count)),
            green: CGFloat(bestGroup.green / Double(bestGroup.count)),
            blue: CGFloat(bestGroup.blue / Double(bestGroup.count)),
            alpha: 1
        ), fingerprint)
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
