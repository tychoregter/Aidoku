//
//  MangaCoverView.swift
//  Aidoku
//
//  Created by Skitty on 9/8/23.
//

import AidokuRunner
import SwiftUI
import UIKit
import Nuke
import NukeUI

enum MangaCoverBorderStyle {
    static func width(displayScale: CGFloat) -> CGFloat {
        2 / max(displayScale, 1)
    }

    static func width(for traits: UITraitCollection) -> CGFloat {
        width(displayScale: traits.displayScale)
    }

    static func color(for traits: UITraitCollection) -> UIColor {
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.24)
            : UIColor.black.withAlphaComponent(0.18)
    }

    static var swiftUIColor: Color {
        Color(uiColor: UIColor { traits in color(for: traits) })
    }
}

struct MangaCoverView: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    @State private var sampledNSFWColor: UIColor?
    @StateObject private var hideNSFWCovers = UserDefaultsBool(key: AppSettings.appearance.blurNSFWCovers.key)

    var source: AidokuRunner.Source?

    let coverImage: String
    var paletteIdentifier: MangaIdentifier?
    var width: CGFloat?
    var height: CGFloat?
    var downsampleWidth: CGFloat?
    var coverDownsampleSide: CGFloat?
    var contentMode: ContentMode = .fill
    var cornerRadius: CGFloat = 12
    var borderColor: Color? = nil
    var placeholder = "MangaPlaceholder"
    var privacyPlaceholder = false
    var usesHiddenCoverColorPlaceholder = false
    var showsCachedCoverImmediately = false
    var hideNSFW = false
    var isNSFW = false
    var nsfwBaseColor: UIColor?
    var onDominantColorChange: ((UIColor) -> Void)?
    var onImageSizeChange: ((CGSize) -> Void)?
    var bookmarked: Bool = false

    private var hidesCover: Bool { hideNSFW || (isNSFW && hideNSFWCovers.value) }

    private var hiddenCoverColor: UIColor {
        CoverPalette.hiddenColor(for: coverImage, dark: colorScheme == .dark)
            ?? NSFWCoverView.backgroundColor(
            for: nsfwBaseColor ?? sampledNSFWColor ?? CoverPalette.color(for: coverImage)
                ?? DeveloperMode.color(for: coverImage),
            isDark: colorScheme == .dark
        )
    }

    var body: some View {
        SourceImageView(
            source: source,
            imageUrl: coverImage,
            width: width,
            height: height,
            downsampleWidth: downsampleWidth,
            coverDownsampleSide: coverDownsampleSide,
            contentMode: contentMode,
            placeholder: placeholder,
            privacyPlaceholder: privacyPlaceholder || hidesCover,
            samplesCoverColor: true,
            usesHiddenCoverColorPlaceholder: usesHiddenCoverColorPlaceholder,
            showsCachedCoverImmediately: showsCachedCoverImmediately,
            paletteIdentifier: paletteIdentifier,
            onDominantColorChange: hidesCover || privacyPlaceholder || onDominantColorChange != nil ? { color in
                if hidesCover || privacyPlaceholder { sampledNSFWColor = color }
                onDominantColorChange?(color)
            } : nil,
            onImageSizeChange: onImageSizeChange
        )
        .overlay {
            if hidesCover || privacyPlaceholder {
                Color(uiColor: hiddenCoverColor)
            }
        }
        .overlay {
            if hidesCover {
                Image(systemName: "eye.slash")
                    .font(.system(size: (width ?? 150) < 80 ? 19 : 32, weight: .semibold))
                    .foregroundStyle(Color(uiColor: CoverPalette.hiddenForegroundColor(
                        for: coverImage, dark: colorScheme == .dark
                    ) ?? NSFWCoverView.foregroundColor(for: hiddenCoverColor)))
            }
        }
        .overlay(
            bookmarkView,
            alignment: .topTrailing
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    borderColor ?? MangaCoverBorderStyle.swiftUIColor,
                    lineWidth: MangaCoverBorderStyle.width(displayScale: displayScale)
                )
        )
        .onChange(of: coverImage) { _ in sampledNSFWColor = nil }
    }

    @ViewBuilder
    var bookmarkView: some View {
        if bookmarked {
            Image("bookmark")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.tint)
                .frame(width: 17, height: 27, alignment: .topTrailing)
                .padding(.trailing, 8)
        } else {
            EmptyView()
        }
    }
}
