//
//  SourceImageView.swift
//  Aidoku
//
//  Created by Skitty on 4/26/25.
//

import AidokuRunner
import Nuke
import NukeUI
import SwiftUI
import UIKit

struct SourceImageView: View {
    @Environment(\.colorScheme) private var colorScheme

    var source: AidokuRunner.Source?

    let imageUrl: String
    var width: CGFloat?
    var height: CGFloat?
    var downsampleWidth: CGFloat?
    var coverDownsampleSide: CGFloat? = nil
    var contentMode: ContentMode = .fill
    var placeholder = "MangaPlaceholder"
    var privacyPlaceholder = false
    var samplesCoverColor = false
    var usesHiddenCoverColorPlaceholder = false
    var showsCachedCoverImmediately = false
    var paletteIdentifier: MangaIdentifier?
    var paletteSamplingPriority: CoverPalette.SamplingPriority = .normal
    var onDominantColorChange: ((UIColor) -> Void)?
    var onImageSizeChange: ((CGSize) -> Void)?

    @State private var imageRequest: ImageRequest?
    @State private var sampledColor: UIColor?
    @State private var sampledColorURL: String?

    private var processors: [ImageProcessing] {
        var processors: [ImageProcessing] = []
        if let coverDownsampleSide {
            processors.append(CoverDownsampleProcessor(shortestSide: coverDownsampleSide))
        } else if let downsampleWidth {
            processors.append(DownsampleProcessor(width: downsampleWidth))
        }
        if let source, source.features.processesCovers {
            processors.append(CoverInterceptorProcessor(source: source))
        }
        return processors
    }

    private func cachedCoverImage() -> UIImage? {
        guard showsCachedCoverImmediately,
              coverDownsampleSide != nil,
              let url = URL(string: imageUrl) else { return nil }

        let urls = [url.toAidokuFileUrl(), url].compactMap { $0 }
        for candidate in urls {
            let request = ImageRequest(
                urlRequest: URLRequest(url: candidate),
                processors: processors,
                userInfo: [.processesKey: source?.features.processesCovers ?? false]
            )
            if let container = ImagePipeline.shared.cache.cachedImage(for: request, caches: [.memory]),
               container.type != .gif {
                return container.image
            }
        }
        return nil
    }

    var body: some View {
        LazyImage(
            request: imageRequest,
            transaction: .init(animation: .default)
        ) { state in
            let cachedImage = state.image == nil && !privacyPlaceholder ? cachedCoverImage() : nil
            let dominantColor = CoverPalette.color(for: imageUrl, identifier: paletteIdentifier)
                ?? (sampledColorURL == imageUrl ? sampledColor : nil)
                ?? DeveloperMode.color(for: imageUrl)
            Group {
                if privacyPlaceholder {
                    Rectangle()
                        .fill(Color(uiColor: dominantColor))
                        .frame(width: width, height: height)
                } else if state.imageContainer?.type == .gif, let data = state.imageContainer?.data {
                    GIFImage(
                        data: data,
                        contentMode: contentMode
                    )
                        .frame(width: width, height: height)
                        .id(state.image != nil ? imageUrl : "placeholder") // ensures only opacity is animated
                } else {
                    Group {
                        if let image = state.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: contentMode)
                        } else if let cachedImage {
                            Image(uiImage: cachedImage)
                                .resizable()
                                .aspectRatio(contentMode: contentMode)
                        } else if usesHiddenCoverColorPlaceholder,
                                  let baseColor = CoverPalette.color(for: imageUrl, identifier: paletteIdentifier)
                                    ?? (sampledColorURL == imageUrl ? sampledColor : nil) {
                            let dark = colorScheme == .dark
                            let placeholderColor = CoverPalette.hiddenColor(for: imageUrl, dark: dark,
                                                                            identifier: paletteIdentifier)
                                ?? NSFWCoverView.backgroundColor(for: baseColor, isDark: dark)
                            Color(uiColor: placeholderColor)
                        } else {
                            Image(placeholder)
                                .resizable()
                                .aspectRatio(contentMode: contentMode)
                        }
                    }
                    .frame(width: width, height: height)
                    .id(state.image != nil ? imageUrl : "placeholder") // ensures only opacity is animated
                }
            }
            .task(id: state.imageContainer.map { ObjectIdentifier($0.image) }) {
                guard samplesCoverColor || privacyPlaceholder || onDominantColorChange != nil,
                      let image = state.imageContainer?.image else { return }
                CoverPalette.observe(
                    image,
                    for: imageUrl,
                    identifier: paletteIdentifier,
                    priority: paletteSamplingPriority
                ) { color in
                    sampledColorURL = imageUrl
                    sampledColor = color
                    onDominantColorChange?(CoverPalette.color(for: imageUrl, identifier: paletteIdentifier) ?? color)
                }
            }
            .task(id: state.imageContainer?.image.size ?? cachedImage?.size) {
                if let size = state.imageContainer?.image.size ?? cachedImage?.size {
                    onImageSizeChange?(size)
                }
            }
        }
        .processors(processors)
        .onAppear {
            guard imageRequest == nil else { return }
            Task {
                await loadImageRequest(url: imageUrl)
            }
        }
        .onChange(of: imageUrl) { newValue in
            imageRequest = nil
            sampledColor = nil
            sampledColorURL = nil
            Task {
                await loadImageRequest(url: newValue)
            }
        }
    }

    func loadImageRequest(url: String) async {
        let url = URL(string: url)
        if let fileUrl = url?.toAidokuFileUrl() {
            imageRequest = ImageRequest(url: fileUrl)
            return
        }
        guard let source, let url, !url.isFileURL else {
            imageRequest = ImageRequest(url: url)
            return
        }
        imageRequest = ImageRequest(
            urlRequest: await source.getModifiedImageRequest(url: url, context: nil),
            userInfo: [.processesKey: source.features.processesCovers]
        )
    }
}
