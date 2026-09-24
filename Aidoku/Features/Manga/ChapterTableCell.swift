//
//  ChapterTableCell.swift
//  Aidoku
//
//  Created by Skitty on 8/17/23.
//

import AidokuRunner
import SwiftUI

struct ChapterTableCell: View {
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
        let view = HStack {
            if let thumbnail = chapter.thumbnail {
                MangaCoverView(
                    source: source,
                    coverImage: thumbnail,
                    width: 40,
                    height: 40
                )
            }

            VStack(alignment: .leading, spacing: 8 / 3) {
                Text(chapter.sourceDisplayTitle)
                    .foregroundStyle(locked || read ? .secondary : .primary)
                    .font(.system(size: 16))
                    .lineLimit(1)
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
                    .imageScale(.small)
                    .foregroundStyle(.tertiary)
            } else if downloadFailed {
                Image(systemName: "exclamationmark.circle.fill")
                    .imageScale(.small)
                    .foregroundStyle(.orange)
            } else if let progress {
                DownloadProgressView(progress: progress)
                    .frame(width: 13, height: 13)
            } else if locked {
                Image(systemName: "lock.fill")
                    .imageScale(.small)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 20)
        .padding(.vertical, 22 / 3)
        .frame(alignment: .leading)
        .contentShape(Rectangle())
        if #available(iOS 16.0, *) {
            view
                .alignmentGuide(.listRowSeparatorTrailing) { d in
                d[.trailing] // ensure separator goes all the way to the trailing edge
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
        if showPageCounts.value, let source, source.legacySource == nil {
            return loadedPageCount.map { String(format: NSLocalizedString("%i_PAGES"), $0) }
        }
        return chapter.formattedSubtitle(page: page, sourceKey: sourceKey)
    }

    private func loadPageCountIfNeeded() async {
        guard showPageCounts.value, loadedPageCount == nil, let source, source.legacySource == nil else { return }
        guard let pages = try? await source.getPageList(manga: manga, chapter: chapter) else { return }
        guard !Task.isCancelled else { return }
        loadedPageCount = pages.count
    }
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
