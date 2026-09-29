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

    var source: AidokuRunner.Source?

    let coverImage: String
    var width: CGFloat?
    var height: CGFloat?
    var downsampleWidth: CGFloat?
    var coverDownsampleSide: CGFloat?
    var contentMode: ContentMode = .fill
    var cornerRadius: CGFloat = 12
    var borderColor: Color? = nil
    var placeholder = "MangaPlaceholder"
    var privacyPlaceholder = false
    var bookmarked: Bool = false

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
            privacyPlaceholder: privacyPlaceholder
        )
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
