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
    var source: AidokuRunner.Source?

    let coverImage: String
    var width: CGFloat?
    var height: CGFloat?
    var downsampleWidth: CGFloat?
    var contentMode: ContentMode = .fill
    var placeholder = "MangaPlaceholder"
    var bookmarked: Bool = false

    var body: some View {
        SourceImageView(
            source: source,
            imageUrl: coverImage,
            width: width,
            height: height,
            downsampleWidth: downsampleWidth,
            contentMode: contentMode,
            placeholder: placeholder
        )
        .overlay(
            bookmarkView,
            alignment: .topTrailing
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(MangaCoverBorderStyle.swiftUIColor, lineWidth: 1)
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
