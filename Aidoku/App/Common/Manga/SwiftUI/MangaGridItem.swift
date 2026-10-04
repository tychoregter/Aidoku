//
//  MangaGridItem.swift
//  Aidoku
//
//  Created by Skitty on 8/16/23.
//

import AidokuRunner
import SwiftUI
import NukeUI

struct MangaGridItem: View {
    @Environment(\.displayScale) private var displayScale

    var source: AidokuRunner.Source?
    let title: String
    let coverImage: String
    var paletteIdentifier: MangaIdentifier?
    var bookmarked: Bool = false
    var isNSFW = false

    static let gradient = Gradient(
        colors: (0...24).map { offset -> Color in
            let ratio = CGFloat(offset) / 24
            return Color.black.opacity(0.7 * pow(ratio, CGFloat(3)))
        }
    )

    var body: some View {
        let view = Rectangle()
            .fill(Color.clear)
            .aspectRatio(2/3, contentMode: .fill)
            .background {
                MangaCoverView(
                    source: source,
                    coverImage: coverImage,
                    paletteIdentifier: paletteIdentifier,
                    coverDownsampleSide: 630,
                    borderColor: .clear,
                    isNSFW: isNSFW
                )
            }
            .overlay(
                bookmarkView,
                alignment: .topTrailing
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        MangaCoverBorderStyle.swiftUIColor,
                        lineWidth: MangaCoverBorderStyle.width(displayScale: displayScale)
                    )
            )
        if coverImage.hasSuffix("gif") {
            // if the image is a gif, we can't use drawingGroup (static image)
            view
        } else {
            view.drawingGroup()
        }
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

    static var placeholder: some View {
        MangaGridItemPlaceholder()
    }
}

private struct MangaGridItemPlaceholder: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Color(uiColor: .secondarySystemFill))
            .aspectRatio(2/3, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        MangaCoverBorderStyle.swiftUIColor,
                        lineWidth: MangaCoverBorderStyle.width(displayScale: displayScale)
                    )
            )
    }
}
