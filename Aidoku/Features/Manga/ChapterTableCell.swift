//
//  ChapterTableCell.swift
//  Aidoku
//
//  Created by Skitty on 8/17/23.
//

import AidokuRunner
import SwiftUI

struct ChapterTableCell: View {
    @Environment(\.displayScale) private var displayScale

    let source: AidokuRunner.Source?
    let manga: AidokuRunner.Manga
    let sourceKey: String
    let chapter: AidokuRunner.Chapter
    let read: Bool
    let page: Int?
    let downloadStatus: DownloadStatus
    var downloadProgress: Float?
    let displayMode: ChapterTitleDisplayMode

    @StateObject private var showPageCounts = UserDefaultsBool(key: AppSettings.library.showChapterPageCounts.key)
    @StateObject private var developerMode = UserDefaultsBool(key: AppSettings.general.developerMode.key)
    @StateObject private var hideNSFWCovers = UserDefaultsBool(key: AppSettings.appearance.blurNSFWCovers.key)
    @State private var loadedPageCount: Int?

    var downloaded: Bool {
        downloadStatus == .finished
    }

    /// A download that stopped with pages missing, which is neither downloaded nor in progress.
    var downloadFailed: Bool {
        downloadStatus == .failed
    }

    var locked: Bool {
        chapter.locked && !downloaded
    }

    var progress: Float? {
        downloadProgress ?? (downloadStatus == .queued || downloadStatus == .downloading ? 0 : nil)
    }

    var body: some View {
        let view = HStack(spacing: 10) {
            MangaCoverView(
                source: source,
                coverImage: chapter.thumbnail ?? manga.cover ?? "",
                width: 56,
                height: 84,
                coverDownsampleSide: 112 * displayScale,
                cornerRadius: 5,
                privacyPlaceholder: developerMode.value,
                hideNSFW: hideNSFWCovers.value && manga.contentRating == .nsfw
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(chapterNumberLabel)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(chapterTitle)
                    .foregroundStyle(locked || read ? .secondary : .primary)
                    .font(.system(size: 16))
                    .lineLimit(2)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if downloaded {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            } else if downloadFailed {
                Image(systemName: "exclamationmark.circle.fill")
                    .imageScale(.small)
                    .foregroundStyle(.orange)
            } else if let progress {
                DownloadProgressView(progress: progress)
                    .frame(width: 13, height: 13)
            }
        }
        .foregroundStyle(.primary)
        .padding(.leading, 20)
        .padding(.trailing, 5)
        .padding(.vertical, 12)
        .frame(alignment: .leading)
        .contentShape(Rectangle())
        if #available(iOS 16.0, *) {
            view
                .alignmentGuide(.listRowSeparatorLeading) { d in
                    d[.leading] + 20 + 56 + 10
                }
                .task(id: "\(chapter.key)-\(showPageCounts.value)") {
                    await loadPageCountIfNeeded()
                }
        } else {
            view.task {
                await loadPageCountIfNeeded()
            }
        }
    }

    private var subtitle: String? {
        if developerMode.value {
            let count = DeveloperMode.pageCount(for: chapter.key)
            return chapterPageCountSubtitle(pageCount: count, progressPage: page)
        }
        if showPageCounts.value, supportsPageCounts {
            if let loadedPageCount {
                return chapterPageCountSubtitle(pageCount: loadedPageCount, progressPage: page)
            }
        }
        return chapter.formattedSubtitle(page: page, sourceKey: sourceKey)
    }

    private var chapterTitle: String {
        if developerMode.value { return DeveloperMode.chapterTitle(for: chapter.key) }
        if let title = chapter.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        return chapter.sourceDisplayTitle
    }

    private var chapterNumberLabel: String {
        let label = NSLocalizedString("CHAPTER").uppercased()
        guard let number = chapter.chapterNumber ?? chapter.volumeNumber, number.isFinite else {
            return label
        }
        return "\(label) \(String(format: "%g", number))"
    }

    private var supportsPageCounts: Bool {
        ["komga", "kavita", "suwayomi"].contains { sourceKey.hasPrefix($0) }
    }

    private func loadPageCountIfNeeded() async {
        guard showPageCounts.value, supportsPageCounts, loadedPageCount == nil, let source else { return }
        guard let pages = try? await source.getPageList(manga: manga, chapter: chapter) else { return }
        guard !Task.isCancelled else { return }
        loadedPageCount = pages.count
    }
}

func chapterPageCountSubtitle(pageCount: Int, progressPage: Int?) -> String {
    let pageCountText = String(format: NSLocalizedString("%i_PAGES"), pageCount)
    guard let progressPage, progressPage > 0 else { return pageCountText }
    let pagesLeft = max(pageCount - progressPage, 0)
    let pagesLeftText = String(format: NSLocalizedString("%i_PAGES_LEFT"), pagesLeft)
    return "\(pageCountText) · \(pagesLeftText)"
}

private struct DownloadProgressView: UIViewRepresentable {
    var progress: Float

    func makeUIView(context: Context) -> CircularProgressView {
        let progressView = CircularProgressView(frame: CGRect(x: 0, y: 0, width: 13, height: 13))
        progressView.radius = 13 / 2
        progressView.trackColor = .quaternaryLabel
        progressView.progressColor = progressView.tintColor
        return progressView
    }

    func updateUIView(_ uiView: CircularProgressView, context: Context) {
        uiView.setProgress(value: progress, withAnimation: false)
    }
}
