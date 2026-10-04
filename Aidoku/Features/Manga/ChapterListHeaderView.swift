//
//  ChapterListHeaderView.swift
//  Aidoku
//
//  Created by Skitty on 4/23/25.
//

import SwiftUI
import UIKit
import AidokuRunner

struct ChapterListHeaderView: View {
    @Binding var sortOption: ChapterSortOption
    @Binding var sortAscending: Bool

    @Binding var filters: [ChapterFilterOption]
    @Binding var langFilter: String?
    @Binding var scanlatorFilter: [String]

    @Binding var displayMode: ChapterTitleDisplayMode

    private var languages: [String] = []
    private var scanlators: [String] = []
    private var mangaId: MangaIdentifier
    private var usesLightMenuLabel: Bool
    private var onReset: () -> Void
    private var missingBooksCount = 0

    init(
        allChapters: [AidokuRunner.Chapter]? = nil,
        visibleChapters: [AidokuRunner.Chapter]? = nil,
        sortOption: Binding<ChapterSortOption>,
        sortAscending: Binding<Bool>,
        filters: Binding<[ChapterFilterOption]>,
        langFilter: Binding<String?>,
        scanlatorFilter: Binding<[String]>,
        displayMode: Binding<ChapterTitleDisplayMode>,
        mangaId: MangaIdentifier,
        usesLightMenuLabel: Bool = false,
        onReset: @escaping () -> Void = {}
    ) {
        self._sortOption = sortOption
        self._sortAscending = sortAscending
        self._filters = filters
        self._langFilter = langFilter
        self._scanlatorFilter = scanlatorFilter
        self._displayMode = displayMode
        self.mangaId = mangaId
        self.usesLightMenuLabel = usesLightMenuLabel
        self.onReset = onReset
        self.missingBooksCount = BookGapPresentation.totalMissingCount(in: visibleChapters ?? allChapters ?? [])

        if let allChapters, !allChapters.isEmpty {
            var languages: Set<String> = []
            var scanlators: Set<String> = []
            for chapter in allChapters {
                if let chapterScanlators = chapter.scanlators, !chapterScanlators.isEmpty {
                    for scanlator in chapterScanlators {
                        scanlators.insert(scanlator)
                    }
                } else {
                    scanlators.insert("")
                }
                if let lang = chapter.language {
                    languages.insert(lang)
                }
            }
            self.languages = languages.sorted()
            self.scanlators = scanlators.sorted()
        }
    }

    var body: some View {
        HStack {
            Text(NSLocalizedString("CHAPTERS"))
                .font(.system(size: 20, weight: .semibold))
                .id("chapters")

            if missingBooksCount > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(BookGapPresentation.label(for: missingBooksCount))
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                }
                .foregroundStyle(Color(uiColor: .systemOrange))
                .padding(.leading, 6)
            }

            Spacer()

        }
    }

    var menu: some View {
        ChapterListMenuButton(
            sortOption: $sortOption,
            sortAscending: $sortAscending,
            filters: $filters,
            langFilter: $langFilter,
            scanlatorFilter: $scanlatorFilter,
            languages: languages,
            scanlators: scanlators,
            usesLightMenuLabel: usesLightMenuLabel,
            onReset: onReset
        )
        .frame(width: 24, height: 24)
    }
}

enum BookGapPresentation {
    static func label(for count: Int) -> String {
        count == 1
            ? NSLocalizedString("MISSING_ONE_BOOK")
            : String(format: NSLocalizedString("MISSING_BOOKS_COUNT"), count)
    }

    static func number(for chapter: AidokuRunner.Chapter) -> Float? {
        guard let number = chapter.chapterNumber ?? chapter.volumeNumber,
              number.isFinite else { return nil }
        return number
    }

    static func isNumberedOrder(_ chapters: [AidokuRunner.Chapter]) -> Bool {
        let numbers = chapters.compactMap { number(for: $0) }
        return zip(numbers, numbers.dropFirst()).allSatisfy { $0.0 <= $0.1 }
            || zip(numbers, numbers.dropFirst()).allSatisfy { $0.0 >= $0.1 }
    }

    static func missingCount(between first: AidokuRunner.Chapter, and second: AidokuRunner.Chapter) -> Int {
        guard let firstNumber = number(for: first),
              let secondNumber = number(for: second) else { return 0 }
        return missingCount(between: firstNumber, and: secondNumber)
    }

    static func totalMissingCount(in chapters: [AidokuRunner.Chapter]) -> Int {
        guard isNumberedOrder(chapters) else { return 0 }
        return zip(chapters, chapters.dropFirst()).reduce(0) { total, pair in
            total + missingCount(between: pair.0, and: pair.1)
        }
    }

    private static func missingCount(between first: Float, and second: Float) -> Int {
        let lower = min(first, second)
        let upper = max(first, second)
        guard lower >= 0, upper < 1_000_000, upper - lower <= 1_000 else { return 0 }

        let firstMissing = Int(floor(lower)) + 1
        // A .1 book starts a fractional sequence and fills its whole-number slot;
        // later fractional entries such as .2 or .5 do not imply that start exists.
        let startsFractionalSequence = abs(upper - floor(upper) - 0.1) < 0.005
        let lastMissing = Int(ceil(upper)) - (startsFractionalSequence ? 2 : 1)
        return max(lastMissing - firstMissing + 1, 0)
    }
}

struct MissingBooksWarningRow: View {
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
            Text(BookGapPresentation.label(for: count))
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(Color(uiColor: .systemOrange))
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .listRowInsets(.zero)
        .listRowBackground(
            Color(uiColor: .systemBackground)
                .overlay(Color(uiColor: .systemOrange).opacity(0.16))
        )
        .listRowSeparator(.hidden, edges: .all)
    }
}

private struct ChapterListMenuButton: UIViewRepresentable {
    @Binding var sortOption: ChapterSortOption
    @Binding var sortAscending: Bool
    @Binding var filters: [ChapterFilterOption]
    @Binding var langFilter: String?
    @Binding var scanlatorFilter: [String]

    let languages: [String]
    let scanlators: [String]
    let usesLightMenuLabel: Bool
    let onReset: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.configuration = .plain()
        button.accessibilityLabel = NSLocalizedString("SORT_BY")
        button.showsMenuAsPrimaryAction = true
        context.coordinator.button = button
        button.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak coordinator = context.coordinator] completion in
            completion(coordinator?.makeMenu().children ?? [])
        }])
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.parent = self
        let appearance: UIUserInterfaceStyle = usesLightMenuLabel ? .dark : .light
        if button.overrideUserInterfaceStyle != appearance {
            button.overrideUserInterfaceStyle = appearance
        }
        let color: UIColor = usesLightMenuLabel ? .white : .black
        if context.coordinator.iconColor != color {
            var configuration = button.configuration ?? .plain()
            configuration.image = UIImage(
                systemName: "line.3.horizontal.decrease",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 17)
            )?.withTintColor(color, renderingMode: .alwaysOriginal)
            configuration.baseForegroundColor = color
            button.configuration = configuration
            button.tintColor = color
            context.coordinator.iconColor = color
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        CGSize(width: 24, height: 24)
    }

    final class Coordinator {
        var parent: ChapterListMenuButton
        weak var button: UIButton?
        var iconColor: UIColor?

        init(_ parent: ChapterListMenuButton) {
            self.parent = parent
        }

        func makeMenu() -> UIMenu {
            let defaultOrder = ChapterListOrder.current
            let visibleOption = parent.sortOption == .default ? defaultOrder.sortOption : parent.sortOption
            let visibleAscending = parent.sortOption == .default
                ? defaultOrder.sortAscending
                : parent.sortAscending
            let sortMenu = UIMenu(
                title: NSLocalizedString("SORT_BY"),
                subtitle: visibleOption.stringValue,
                image: UIImage(systemName: "arrow.up.arrow.down"),
                children: [UIMenu(options: .displayInline, children: ChapterSortOption.allCases.map { option in
                    let selected = visibleOption == option
                    return UIAction(
                        title: option.stringValue,
                        subtitle: selected && option != .automatic
                            ? NSLocalizedString(visibleAscending ? "ASCENDING" : "DESCENDING")
                            : nil,
                        attributes: .keepsMenuPresented,
                        state: selected ? .on : .off
                    ) { [weak self] _ in
                        guard let self else { return }
                        if option == .automatic {
                            self.parent.sortOption = .automatic
                        } else if visibleOption == option {
                            self.parent.sortAscending = !visibleAscending
                            self.parent.sortOption = option
                        } else {
                            self.parent.sortAscending = true
                            self.parent.sortOption = option
                        }
                        self.refreshMenu()
                    }
                })]
            )

            var filterChildren: [UIMenuElement] = ChapterFilterMethod.allCases.map { method in
                let filter = parent.filters.first { $0.type == method }
                let state: UIMenuElement.State = filter.map { $0.exclude ? .mixed : .on } ?? .off
                return UIAction(
                    title: filterTitle(for: method),
                    image: UIImage(systemName: imageName(for: method)),
                    attributes: .keepsMenuPresented,
                    state: state
                ) { [weak self] _ in
                    guard let self else { return }
                    if let index = self.parent.filters.firstIndex(where: { $0.type == method }) {
                        if self.parent.filters[index].exclude {
                            self.parent.filters.remove(at: index)
                        } else {
                            self.parent.filters[index].exclude = true
                        }
                    } else {
                        self.parent.filters.append(.init(type: method, exclude: false))
                    }
                    self.refreshMenu()
                }
            }

            if parent.languages.count > 1 {
                filterChildren.append(UIMenu(
                    title: NSLocalizedString("LANGUAGE"),
                    subtitle: parent.langFilter.map { SourceLanguage.displayName(for: $0) },
                    image: UIImage(systemName: "globe"),
                    children: parent.languages.map { language in
                        UIAction(
                            title: SourceLanguage.displayName(for: language),
                            attributes: .keepsMenuPresented,
                            state: parent.langFilter == language ? .on : .off
                        ) { [weak self] _ in
                            guard let self else { return }
                            self.parent.langFilter = self.parent.langFilter == language ? nil : language
                            self.refreshMenu()
                        }
                    }
                ))
            }

            if parent.scanlators.count > 1 {
                filterChildren.append(UIMenu(
                    title: NSLocalizedString("SCANLATOR"),
                    subtitle: subtitle(for: parent.scanlatorFilter.map { scanlatorTitle($0) }),
                    image: UIImage(systemName: "person.2"),
                    children: parent.scanlators.map { scanlator in
                        UIAction(
                            title: scanlatorTitle(scanlator),
                            attributes: .keepsMenuPresented,
                            state: parent.scanlatorFilter.contains(scanlator) ? .on : .off
                        ) { [weak self] _ in
                            guard let self else { return }
                            if let index = self.parent.scanlatorFilter.firstIndex(of: scanlator) {
                                self.parent.scanlatorFilter.remove(at: index)
                            } else {
                                self.parent.scanlatorFilter.append(scanlator)
                            }
                            self.refreshMenu()
                        }
                    }
                ))
            }

            let filterMenu = UIMenu(
                title: NSLocalizedString("BUTTON_FILTER"),
                subtitle: filtersSubtitle(),
                image: UIImage(systemName: "line.3.horizontal.decrease"),
                children: filterChildren
            )
            var sections = [UIMenu(options: .displayInline, children: [sortMenu, filterMenu])]
            if parent.sortOption != .default
                || !parent.filters.isEmpty
                || parent.langFilter != nil
                || !parent.scanlatorFilter.isEmpty {
                let resetAction = UIAction(
                    title: NSLocalizedString("RESET"),
                    image: UIImage(systemName: "arrow.counterclockwise")
                ) { [weak self] _ in
                    self?.parent.onReset()
                    self?.refreshMenu()
                }
                sections.append(UIMenu(options: .displayInline, children: [resetAction]))
            }
            return UIMenu(children: sections)
        }

        private func refreshMenu() {
            let updatedMenu = makeMenu()
            if let interaction = button?.interactions.compactMap({ $0 as? UIContextMenuInteraction }).first {
                interaction.updateVisibleMenu { visibleMenu in
                    self.menu(titled: visibleMenu.title, in: updatedMenu) ?? updatedMenu
                }
            }
        }

        private func menu(titled title: String, in menu: UIMenu) -> UIMenu? {
            if menu.title == title { return menu }
            for child in menu.children {
                if let child = child as? UIMenu, let match = self.menu(titled: title, in: child) {
                    return match
                }
            }
            return nil
        }

        private func imageName(for method: ChapterFilterMethod) -> String {
            switch method {
                case .downloaded: "arrow.down.circle"
                case .unread: "eye.slash"
                case .locked: "lock"
            }
        }

        private func filterTitle(for method: ChapterFilterMethod) -> String {
            method == .unread ? NSLocalizedString("FILTER_HAS_UNREAD") : method.stringValue
        }

        private func scanlatorTitle(_ scanlator: String) -> String {
            scanlator.isEmpty ? NSLocalizedString("NO_SCANLATOR") : scanlator
        }

        private func subtitle(for values: [String]) -> String? {
            guard !values.isEmpty else { return nil }
            let displayed = values.count > 3
                ? Array(values.prefix(2)) + [NSLocalizedString("AND_MORE")]
                : values
            return displayed.joined(separator: NSLocalizedString("FILTER_SEPARATOR"))
        }

        private func filtersSubtitle() -> String? {
            var values = parent.filters.map { filter in
                filter.exclude
                    ? String(format: NSLocalizedString("NOT_%@"), filterTitle(for: filter.type))
                    : filterTitle(for: filter.type)
            }
            if let language = parent.langFilter {
                values.append(SourceLanguage.displayName(for: language))
            }
            values.append(contentsOf: parent.scanlatorFilter.map { scanlatorTitle($0) })
            return subtitle(for: values)
        }
    }
}
