import AppIntents
import SwiftUI
import UIKit
import WidgetKit

private let appGroup = "group.io.orangebyte.Aidoku"

struct WidgetItem: Codable, Hashable {
    let sourceKey: String
    let mangaKey: String
    let title: String
    let coverURL: String?
    let coverFilename: String?
    let position: String?
    let volume: String?
    let pagesLeft: Int?
    let atVolumeStart: Bool?
    let completionStatus: String?
    let unreadCount: Int
    let contentRating: Int
    let lastRead: Date?
    let lastOpened: Date?
    let lastUpdated: Date?
    let dateAdded: Date
    let lastChapter: Date?
    let totalChapters: Int
    var id: String { sourceKey + "." + mangaKey }
}

struct WidgetSnapshot: Codable { let updatedAt: Date; let groups: [String: [WidgetItem]] }

enum WidgetPin: String, AppEnum {
    case all, favorites, started, unread, completed, updatedChapters
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Library Content")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .all: "Full Library", .favorites: "Favorites", .started: "Continue Reading", .unread: "Unread", .completed: "Ended", .updatedChapters: "Updated"
    ]
    var title: String {
        switch self { case .all: "Library"; case .favorites: "Favorites"; case .started: "Continue Reading"; case .unread: "Unread"; case .completed: "Ended"; case .updatedChapters: "Updated" }
    }
}

enum WidgetRating: String, AppEnum {
    case all, safeAndSuggestive, safeOnly
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Maximum Content Rating")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.all: "All", .safeAndSuggestive: "Safe and Suggestive", .safeOnly: "Safe Only"]
    var maximum: Int { self == .all ? Int.max : self == .safeAndSuggestive ? 1 : 0 }
}

enum WidgetSort: String, AppEnum {
    case title, lastRead, lastOpened, lastUpdated, dateAdded, lastChapter, unread, total
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Sort By")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .title: "Title", .lastRead: "Last Read", .lastOpened: "Last Opened", .lastUpdated: "Last Updated", .dateAdded: "Date Added", .lastChapter: "Latest Chapter", .unread: "Unread Chapters", .total: "Total Chapters"
    ]
}

struct WidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Library Widget"
    static let description = IntentDescription("Show pinned titles from your Aidoku library.")
    @Parameter(title: "Library Content", default: .favorites) var pin: WidgetPin
    @Parameter(title: "Maximum Content Rating", default: .all) var rating: WidgetRating
    @Parameter(title: "Only Show Unread", default: false) var onlyUnread: Bool
    @Parameter(title: "Sort By", default: .lastRead) var sort: WidgetSort
    @Parameter(title: "Ascending", default: false) var ascending: Bool
    init() { pin = .favorites; rating = .all; onlyUnread = false; sort = .lastRead; ascending = false }
}

enum WidgetLayout { case list, grid }
struct WidgetEntry: TimelineEntry { let date: Date; let intent: WidgetIntent; let layout: WidgetLayout; let items: [WidgetItem] }

struct WidgetProvider: AppIntentTimelineProvider {
    let layout: WidgetLayout
    func placeholder(in context: Context) -> WidgetEntry { WidgetEntry(date: .now, intent: WidgetIntent(), layout: layout, items: []) }
    func snapshot(for intent: WidgetIntent, in context: Context) async -> WidgetEntry { makeEntry(intent) }
    func timeline(for intent: WidgetIntent, in context: Context) async -> Timeline<WidgetEntry> { Timeline(entries: [makeEntry(intent)], policy: .after(.now.addingTimeInterval(1800))) }
    private func makeEntry(_ intent: WidgetIntent) -> WidgetEntry {
        let snapshot = load(), pin = intent.pin, rating = intent.rating, onlyUnread = intent.onlyUnread, sort = intent.sort, ascending = intent.ascending
        var items = snapshot?.groups[pin.rawValue] ?? []
        items = items.filter { $0.contentRating <= rating.maximum && (!onlyUnread || $0.unreadCount > 0) }
        items.sort { a, b in
            let result: ComparisonResult = switch sort {
            case .title: a.title.localizedStandardCompare(b.title)
            case .lastRead: compare(a.lastRead, b.lastRead)
            case .lastOpened: compare(a.lastOpened, b.lastOpened)
            case .lastUpdated: compare(a.lastUpdated, b.lastUpdated)
            case .dateAdded: compare(a.dateAdded, b.dateAdded)
            case .lastChapter: compare(a.lastChapter, b.lastChapter)
            case .unread: compare(a.unreadCount, b.unreadCount)
            case .total: compare(a.totalChapters, b.totalChapters)
            }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
        return WidgetEntry(date: snapshot?.updatedAt ?? .now, intent: intent, layout: layout, items: items)
    }
    private func load() -> WidgetSnapshot? {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appendingPathComponent("library-widget-snapshot.json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
    private func compare<T: Comparable>(_ a: T?, _ b: T?) -> ComparisonResult {
        switch (a, b) { case let (a?, b?) where a < b: .orderedAscending; case let (a?, b?) where a > b: .orderedDescending; case (nil, nil): .orderedSame; case (nil, _): .orderedAscending; default: .orderedDescending }
    }
    private func compare<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult { a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame }
}

struct WidgetView: View {
    let entry: WidgetEntry
    @Environment(\.widgetFamily) private var family
    private var pinTitle: String { entry.intent.pin.title }
    private var items: [WidgetItem] {
        let count: Int = switch (family, entry.layout) { case (.systemSmall, _): 1; case (.systemMedium, .list): 2; case (.systemMedium, .grid): 4; case (.systemLarge, .list): 5; case (.systemLarge, .grid): 12; default: 1 }
        return Array(entry.items.prefix(count))
    }
    var body: some View {
        Group {
            if items.isEmpty { ContentUnavailableView("No Titles", systemImage: "books.vertical") }
            else if family == .systemSmall { SmallWidgetView(item: items[0]) }
            else if entry.layout == .grid {
                GeometryReader { proxy in
                    let rows = family == .systemLarge ? 3 : 1
                    let rowSpacing: CGFloat = 10
                    let titleHeight: CGFloat = 22
                    let coverHeight = max(1, (proxy.size.height - titleHeight - 10 - CGFloat(rows - 1) * rowSpacing) / CGFloat(rows))
                    VStack(alignment: .leading, spacing: 11) {
                        Text(pinTitle).font(.system(size: 16.5, weight: .semibold)).foregroundStyle(.pink).lineLimit(1)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 18), count: 4), spacing: rowSpacing) {
                            ForEach(0..<(family == .systemLarge ? 12 : 4), id: \.self) { index in
                                if index < items.count {
                                    let item = items[index]
                                    CoverLink(item: item) {
                                        Cover(item: item)
                                            .frame(width: coverHeight * 2 / 3, height: coverHeight)
                                    }
                                } else {
                                    PlaceholderCover()
                                        .frame(width: coverHeight * 2 / 3, height: coverHeight)
                                }
                            }
                        }
                    }
                }
            } else {
                GeometryReader { proxy in
                    let largeList = family == .systemLarge
                    let rowCount = largeList ? 5 : 2
                    let rowSpacing: CGFloat = 10
                    let titleHeight: CGFloat = 22
                    let posterHeight = largeList
                        ? max(1, (proxy.size.height - titleHeight - 11 - CGFloat(rowCount - 1) * rowSpacing) / CGFloat(rowCount))
                        : 48
                    VStack(alignment: .leading, spacing: 11) {
                        Text(pinTitle).font(.system(size: 16.5, weight: .semibold)).foregroundStyle(.pink)
                        VStack(spacing: rowSpacing) {
                            ForEach(items, id: \.id) {
                                ListItem(
                                    item: $0,
                                    posterWidth: largeList ? posterHeight * 2 / 3 : 32,
                                    posterHeight: largeList ? posterHeight : 48,
                                    allowsTwoLineTitle: largeList
                                )
                            }
                        }
                    }
                }
            }
        }
        .containerBackground(.background, for: .widget)
        .padding(.horizontal, family == .systemSmall ? 0 : 19)
        .padding(.top, family == .systemSmall ? 0 : 17)
        .padding(.bottom, family == .systemSmall ? 0 : 17)
    }
}

private struct SmallWidgetView: View {
    let item: WidgetItem
    var body: some View {
        CoverLink(item: item) {
            GeometryReader { proxy in
                ZStack(alignment: .bottomLeading) {
                    Cover(item: item)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).font(.headline).bold().lineLimit(2)
                        Text(item.widgetPosition(for: true)).font(.caption).lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottomLeading)
                }
                .clipped()
            }
        }
    }
}

private struct ListItem: View {
    let item: WidgetItem
    let posterWidth: CGFloat
    let posterHeight: CGFloat
    let allowsTwoLineTitle: Bool
    var body: some View {
        CoverLink(item: item) {
            HStack(spacing: 8) {
                Cover(item: item).frame(width: posterWidth, height: posterHeight)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.subheadline.bold()).lineLimit(allowsTwoLineTitle ? 2 : 1).fixedSize(horizontal: false, vertical: true)
                    Text(item.widgetPosition(for: false)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
        }
    }
}

private struct CoverLink<Content: View>: View {
    let item: WidgetItem
    @ViewBuilder let content: () -> Content
    init(item: WidgetItem, @ViewBuilder content: @escaping () -> Content) { self.item = item; self.content = content }
    var body: some View { Link(destination: URL(string: "aidoku://widget/\(item.sourceKey)/\(item.mangaKey)")!, label: content) }
}

private struct Cover: View {
    let item: WidgetItem

    @ViewBuilder
    private var imageContent: some View {
        if let filename = item.coverFilename,
           let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup),
           let image = UIImage(contentsOfFile: directory.appendingPathComponent("WidgetCovers").appendingPathComponent(filename).path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Color.secondary.opacity(0.15)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            // The caller supplies an exact 2:3 frame. Apply those final
            // dimensions to the image itself before clipping so the source
            // image's intrinsic aspect ratio cannot affect the result.
            imageContent
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct PlaceholderCover: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.secondary.opacity(0.15))
    }
}

private extension WidgetItem {
    func widgetPosition(for small: Bool) -> String {
        if let completionStatus { return completionStatus }
        if let volume {
            if atVolumeStart == true { return small ? "Start chapter \(volume)" : "Start reading chapter \(volume)" }
            if let pagesLeft { return "Chapter \(volume), \(pagesLeft)% read" }
            return "Chapter \(volume)"
        }
        return position ?? ""
    }
}

struct AidokuListWidget: Widget {
    let kind = "AidokuListWidget"
    var body: some WidgetConfiguration { AppIntentConfiguration(kind: kind, intent: WidgetIntent.self, provider: WidgetProvider(layout: .list)) { WidgetView(entry: $0) }.configurationDisplayName("Library List").description("See your pinned Aidoku titles in a list.").supportedFamilies([.systemMedium, .systemLarge]).contentMarginsDisabled() }
}

struct AidokuGridWidget: Widget {
    let kind = "AidokuGridWidget"
    var body: some WidgetConfiguration { AppIntentConfiguration(kind: kind, intent: WidgetIntent.self, provider: WidgetProvider(layout: .grid)) { WidgetView(entry: $0) }.configurationDisplayName("Library Grid").description("See your pinned Aidoku covers.").supportedFamilies([.systemMedium, .systemLarge]).contentMarginsDisabled() }
}

struct AidokuSmallWidget: Widget {
    let kind = "AidokuSmallWidget"
    var body: some WidgetConfiguration { AppIntentConfiguration(kind: kind, intent: WidgetIntent.self, provider: WidgetProvider(layout: .list)) { WidgetView(entry: $0) }.configurationDisplayName("Library Small").description("See one pinned Aidoku title.").supportedFamilies([.systemSmall]).contentMarginsDisabled() }
}

@main struct AidokuWidgetBundle: WidgetBundle { var body: some Widget { AidokuSmallWidget(); AidokuListWidget(); AidokuGridWidget() } }
