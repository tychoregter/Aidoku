//
//  MultiSelectFilterView.swift
//  Aidoku
//
//  Created by Skitty on 10/16/23.
//

import AidokuRunner
import SwiftUI
import UIKit

struct MultiSelectFilterView: View {
    let filter: AidokuRunner.Filter
    let usesLibrarySelectionStyle: Bool

    @Binding var enabledFilters: [FilterValue]

    private let multiSelectFilter: MultiSelectFilter

    @State private var showingSheet = false
    @State private var includedOptions: [String]
    @State private var excludedOptions: [String]

    init(
        filter: AidokuRunner.Filter,
        enabledFilters: Binding<[FilterValue]>,
        usesLibrarySelectionStyle: Bool = false
    ) {
        self.filter = filter
        self._enabledFilters = enabledFilters
        self.usesLibrarySelectionStyle = usesLibrarySelectionStyle

        if case let .multiselect(filter) = filter.value {
            self.multiSelectFilter = filter
        } else {
            fatalError("invalid filter type")
        }

        let defaultIncluded = multiSelectFilter.defaultIncluded ?? []
        let defaultExcluded = multiSelectFilter.defaultExcluded ?? []

        if
            let enabledValue = enabledFilters.wrappedValue.first(where: { $0.id == filter.id }),
            case let .multiselect(_, included, excluded) = enabledValue
        {
            self._includedOptions = State(initialValue: included)
            self._excludedOptions = State(initialValue: excluded)
        } else {
            self._includedOptions = State(initialValue: defaultIncluded)
            self._excludedOptions = State(initialValue: defaultExcluded)
        }
    }

    var isDefault: Bool {
        includedOptions == (multiSelectFilter.defaultIncluded ?? [])
            && excludedOptions == (multiSelectFilter.defaultExcluded ?? [])
    }

    var body: some View {
        Group {
            let label = FilterLabelView(
                name: filter.title ?? "",
                badgeCount: isDefault ? 0 : includedOptions.count + excludedOptions.count,
                chevron: true
            )
            if usesLibrarySelectionStyle {
                LibraryStyleMultiSelectMenuButton(
                    options: multiSelectFilter.options.enumerated().map { offset, option in
                        (title: option, id: multiSelectFilter.ids?[safe: offset] ?? option)
                    },
                    canExclude: multiSelectFilter.canExclude,
                    includedOptions: $includedOptions,
                    excludedOptions: $excludedOptions,
                    accessibilityLabel: filter.title ?? "",
                    badgeCount: isDefault ? 0 : includedOptions.count + excludedOptions.count
                )
            } else {
                Menu {
                    ForEach(Array(multiSelectFilter.options.enumerated()), id: \.offset) { offset, option in
                        let id = multiSelectFilter.ids?[safe: offset] ?? option
                        Button {
                            toggle(option: id)
                        } label: {
                            HStack {
                                Text(option)
                                Spacer()
                                if includedOptions.contains(id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                } else if multiSelectFilter.canExclude, excludedOptions.contains(id) {
                                    Image(systemName: "xmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .menuActionDismissDisabled()
                    }
                } label: {
                    label
                }
            }
        }
        .sheet(isPresented: $showingSheet) {
            PlatformNavigationStack {
                ScrollView(.vertical) {
                    MultiSelectFilterGroupView(
                        filter: filter,
                        includedOptions: $includedOptions,
                        excludedOptions: $excludedOptions
                    )
                }
                .navigationTitle(filter.title?.localizedCapitalized ?? "")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .onChange(of: includedOptions) { _ in
            updateFilter()
        }
        .onChange(of: excludedOptions) { _ in
            updateFilter()
        }
        .onChange(of: enabledFilters) { _ in
            if let enabledFilter = enabledFilters.first(where: { $0.id == filter.id }) {
                if case let .multiselect(_, included, excluded) = enabledFilter {
                    includedOptions = included
                    excludedOptions = excluded
                }
            } else {
                includedOptions = multiSelectFilter.defaultIncluded ?? []
                excludedOptions = multiSelectFilter.defaultExcluded ?? []
            }
        }
    }

    func toggle(option: String) {
        if let index = includedOptions.firstIndex(of: option) {
            let result = includedOptions.remove(at: index)
            if multiSelectFilter.canExclude {
                excludedOptions.append(result)
            }
        } else if multiSelectFilter.canExclude, let index = excludedOptions.firstIndex(of: option) {
            excludedOptions.remove(at: index)
        } else {
            includedOptions.append(option)
        }
    }

    func updateFilter() {
        let filterValue = FilterValue.multiselect(id: filter.id, included: includedOptions, excluded: excludedOptions)

        if let index = enabledFilters.firstIndex(where: { $0.id == filter.id }) {
            if isDefault {
                enabledFilters.remove(at: index)
            } else {
                enabledFilters[index] = filterValue
            }
        } else if !isDefault {
            enabledFilters.append(filterValue)
        }
    }
}

private struct LibraryStyleMultiSelectMenuButton: UIViewRepresentable {
    let options: [(title: String, id: String)]
    let canExclude: Bool
    @Binding var includedOptions: [String]
    @Binding var excludedOptions: [String]
    let accessibilityLabel: String
    let badgeCount: Int

    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> LibraryStyleFilterMenuButtonView {
        let button = LibraryStyleFilterMenuButtonView()
        button.accessibilityLabel = accessibilityLabel
        button.update(title: accessibilityLabel, badgeCount: badgeCount, active: badgeCount > 0, darkMode: colorScheme == .dark)
        context.coordinator.button = button
        button.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak coordinator = context.coordinator] completion in
            completion(coordinator?.makeMenu().children ?? [])
        }])
        return button
    }

    func updateUIView(_ button: LibraryStyleFilterMenuButtonView, context: Context) {
        context.coordinator.parent = self
        button.accessibilityLabel = accessibilityLabel
        button.update(title: accessibilityLabel, badgeCount: badgeCount, active: badgeCount > 0, darkMode: colorScheme == .dark)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: LibraryStyleFilterMenuButtonView,
        context: Context
    ) -> CGSize? {
        uiView.intrinsicContentSize
    }

    final class Coordinator {
        var parent: LibraryStyleMultiSelectMenuButton
        weak var button: UIButton?

        init(_ parent: LibraryStyleMultiSelectMenuButton) {
            self.parent = parent
        }

        func makeMenu(included: [String]? = nil, excluded: [String]? = nil) -> UIMenu {
            let included = included ?? parent.includedOptions
            let excluded = excluded ?? parent.excludedOptions
            return UIMenu(children: parent.options.map { option in
                let state: UIMenuElement.State = included.contains(option.id) ? .on
                    : (parent.canExclude && excluded.contains(option.id) ? .mixed : .off)
                return UIAction(
                    title: option.title,
                    attributes: .keepsMenuPresented,
                    state: state
                ) { [weak self] _ in
                    self?.toggle(option.id)
                }
            })
        }

        private func toggle(_ id: String) {
            var included = parent.includedOptions
            var excluded = parent.excludedOptions
            if let index = included.firstIndex(of: id) {
                included.remove(at: index)
                if parent.canExclude { excluded.append(id) }
            } else if parent.canExclude, let index = excluded.firstIndex(of: id) {
                excluded.remove(at: index)
            } else {
                included.append(id)
            }
            parent.includedOptions = included
            parent.excludedOptions = excluded

            if let interaction = button?.interactions.compactMap({ $0 as? UIContextMenuInteraction }).first {
                let updatedMenu = makeMenu(included: included, excluded: excluded)
                interaction.updateVisibleMenu { _ in updatedMenu }
            }
        }
    }
}

struct MultiSelectFilterGroupView: View {
    let filter: AidokuRunner.Filter
    var searchText: String?

    @Binding var includedOptions: [String]
    @Binding var excludedOptions: [String]

    struct Option: Identifiable {
        var id = UUID()
        let title: String
        let value: String
    }

    private let multiSelectFilter: MultiSelectFilter
    private let allOptions: [Option]

    @State private var filteredOptions: [Option]

    private enum FilterState {
        case normal
        case included
        case excluded
    }

    init(
        filter: AidokuRunner.Filter,
        searchText: String? = nil,
        includedOptions: Binding<[String]>,
        excludedOptions: Binding<[String]>
    ) {
        self.filter = filter
        self.searchText = searchText
        self._includedOptions = includedOptions
        self._excludedOptions = excludedOptions

        if case let .multiselect(filter) = filter.value {
            self.multiSelectFilter = filter

            self.allOptions = filter.options.enumerated().map { offset, option in
                let id = filter.ids?[safe: offset] ?? option
                return Option(title: option, value: id)
            }
            if let searchText, !searchText.isEmpty {
                self._filteredOptions = State(initialValue: allOptions.filter { $0.title.localizedCaseInsensitiveContains(searchText) })
            } else {
                self._filteredOptions = State(initialValue: allOptions)
            }
        } else {
            fatalError("invalid filter type")
        }
    }

    var body: some View {
        Group {
            if multiSelectFilter.usesTagStyle {
                tagBody
            } else {
                listBody
            }
        }
        .onChange(of: searchText) { newValue in
            if let newValue, !newValue.isEmpty {
                filteredOptions = allOptions.filter { $0.title.localizedCaseInsensitiveContains(newValue) }
            } else {
                filteredOptions = allOptions
            }
        }
    }

    var tagBody: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HCollectionGrid(
                rows: min(Int(multiSelectFilter.options.count / 12), 4) + 1,
                verticalSpacing: 8,
                horizontalSpacing: 8,
                filteredOptions,
                id: \.id
            ) { option in
                let id = option.value
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        toggle(option: id)
                    }
                } label: {
                    Text(option.title)
                }
                .buttonStyle(
                    GenreButtonStyle(state: {
                        if includedOptions.contains(id) {
                            multiSelectFilter.canExclude ? .included : .enabled
                        } else if multiSelectFilter.canExclude, excludedOptions.contains(id) {
                            .excluded
                        } else {
                            .normal
                        }
                    }())
                )
            }
            .padding(.horizontal)
        }
        .scrollClipDisabledPlease()
        .padding(.top, 2)
    }

    var listBody: some View {
        VStack(spacing: 0) {
            ForEach(filteredOptions) { option in
                let id = option.value
                Button {
                    toggle(option: id)
                } label: {
                    HStack {
                        let state: FilterState = if includedOptions.contains(id) {
                            .included
                        } else if multiSelectFilter.canExclude, excludedOptions.contains(id) {
                            .excluded
                        } else {
                            .normal
                        }
                        ZStack {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(state == .normal ? Color(uiColor: .secondarySystemFill) : Color.accentColor)
                                .aspectRatio(1, contentMode: .fill)
                                .frame(width: 24)
                            if state != .normal {
                                Image(systemName: state == .included ? "checkmark" : "xmark")
                                    .foregroundStyle(.white)
                                    .font(.system(size: 14).weight(.semibold))
                            }
                        }
                        Text(option.title)
                            .padding(.leading, 1)
                            .lineLimit(1)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 8)
                    .padding(.horizontal)
                }
                .buttonStyle(SelectHighlightButtonStyle())
            }
        }
    }

    func toggle(option: String) {
        if let index = includedOptions.firstIndex(of: option) {
            let result = includedOptions.remove(at: index)
            if multiSelectFilter.canExclude {
                excludedOptions.append(result)
            }
        } else if multiSelectFilter.canExclude, let index = excludedOptions.firstIndex(of: option) {
            excludedOptions.remove(at: index)
        } else {
            includedOptions.append(option)
        }
    }
}

private struct GenreButtonStyle: ButtonStyle {
    var state: State

    enum State {
        case normal
        case enabled
        case included
        case excluded
    }

    func makeBody(configuration: Configuration) -> some View {
        let foregroundColor = state == .normal ? Color.primary : Color.white
        let backgroundColor = switch state {
            case .normal:
                Color(uiColor: .secondarySystemBackground)
            case .enabled:
                Color.accentColor
            case .included:
                Color.green
            case .excluded:
                Color.red
        }
        return configuration.label
            .font(.callout)
            .padding(.vertical, 5)
            .padding(.horizontal, 12)
            .foregroundStyle(foregroundColor.opacity(configuration.isPressed ? 0.7 : 1))
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
