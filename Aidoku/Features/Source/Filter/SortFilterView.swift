//
//  SortFilterView.swift
//  Aidoku
//
//  Created by Skitty on 10/16/23.
//

import AidokuRunner
import SwiftUI
import UIKit

struct SortFilterView: View {
    let filter: AidokuRunner.Filter
    let usesLibrarySelectionStyle: Bool

    @Binding var enabledFilters: [FilterValue]

    private let canAscend: Bool
    private let options: [String]
    private let defaultValue: AidokuRunner.Filter.SortDefault?

    @State private var selectedOption: Int
    @State private var ascending: Bool

    private var active: Bool {
        (selectedOption != defaultValue?.index ?? 0) || (ascending != defaultValue?.ascending ?? false)
    }

    init(
        filter: AidokuRunner.Filter,
        enabledFilters: Binding<[FilterValue]>,
        usesLibrarySelectionStyle: Bool = false
    ) {
        self.filter = filter
        self._enabledFilters = enabledFilters
        self.usesLibrarySelectionStyle = usesLibrarySelectionStyle

        guard case let .sort(canAscend, options, defaultValue) = filter.value else {
            fatalError("invalid filter type")
        }
        self.canAscend = canAscend
        self.options = options
        self.defaultValue = defaultValue

        if
            let enabledValue = enabledFilters.wrappedValue.first(where: { $0.id == filter.id }),
            case .sort(let value) = enabledValue
        {
            self._selectedOption = State(initialValue: Int(value.index))
            self._ascending = State(initialValue: value.ascending)
        } else {
            self._selectedOption = State(initialValue: defaultValue?.index ?? 0)
            self._ascending = State(initialValue: defaultValue?.ascending ?? false)
        }
    }

    var body: some View {
        Group {
            let label = FilterLabelView(
                name: {
                    if selectedOption >= options.count {
                        NSLocalizedString("INVALID")
                    } else if let title = filter.title {
                        "\(title): \(options[selectedOption])"
                    } else {
                        options[selectedOption]
                    }
                }(),
                active: active,
                chevron: true
            )
            if usesLibrarySelectionStyle {
                LibraryStyleSortMenuButton(
                    options: options,
                    canAscend: canAscend,
                    selectedOption: $selectedOption,
                    ascending: $ascending,
                    accessibilityLabel: filter.title ?? "",
                    displayTitle: selectedOption >= options.count ? NSLocalizedString("INVALID")
                        : (filter.title.map { "\($0): \(options[selectedOption])" } ?? options[selectedOption]),
                    active: active
                )
            } else {
                Menu {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        Button {
                            withAnimation {
                                if selectedOption == index && canAscend {
                                    ascending.toggle()
                                } else {
                                    selectedOption = index
                                    ascending = false
                                }
                            }
                        } label: {
                            HStack {
                                Text(option)
                                if selectedOption == index {
                                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                                }
                            }
                        }
                    }
                } label: {
                    label
                }
            }
        }
        .onChange(of: selectedOption) { _ in
            updateFilter()
        }
        .onChange(of: ascending) { _ in
            updateFilter()
        }
        .onChange(of: enabledFilters) { _ in
            if let enabledFilter = enabledFilters.first(where: { $0.id == filter.id }) {
                if case .sort(let value) = enabledFilter {
                    selectedOption = Int(value.index)
                    ascending = value.ascending
                }
            } else {
                selectedOption = defaultValue?.index ?? 0
                ascending = defaultValue?.ascending ?? false
            }
        }
    }

    func updateFilter() {
        var newEnabledFilters = enabledFilters
        if let index = enabledFilters.firstIndex(where: { $0.id == filter.id }) {
            guard
                case let .sort(filter) = enabledFilters[index],
                filter.index != selectedOption || filter.ascending != ascending
            else {
                return
            }
            newEnabledFilters.remove(at: index)
        }
        if active {
            newEnabledFilters.append(
                FilterValue.sort(.init(
                    id: filter.id,
                    index: selectedOption,
                    ascending: ascending
                ))
            )
        }
        enabledFilters = newEnabledFilters
    }
}

private struct LibraryStyleSortMenuButton: UIViewRepresentable {
    let options: [String]
    let canAscend: Bool
    @Binding var selectedOption: Int
    @Binding var ascending: Bool
    let accessibilityLabel: String
    let displayTitle: String
    let active: Bool

    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> LibraryStyleFilterMenuButtonView {
        let button = LibraryStyleFilterMenuButtonView()
        button.accessibilityLabel = accessibilityLabel
        button.update(title: displayTitle, active: active, darkMode: colorScheme == .dark)
        context.coordinator.button = button
        button.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak coordinator = context.coordinator] completion in
            completion(coordinator?.makeMenu().children ?? [])
        }])
        return button
    }

    func updateUIView(_ button: LibraryStyleFilterMenuButtonView, context: Context) {
        context.coordinator.parent = self
        button.accessibilityLabel = accessibilityLabel
        button.update(title: displayTitle, active: active, darkMode: colorScheme == .dark)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: LibraryStyleFilterMenuButtonView,
        context: Context
    ) -> CGSize? {
        uiView.intrinsicContentSize
    }

    final class Coordinator {
        var parent: LibraryStyleSortMenuButton
        weak var button: UIButton?

        init(_ parent: LibraryStyleSortMenuButton) {
            self.parent = parent
        }

        func makeMenu(selected: Int? = nil, ascending: Bool? = nil) -> UIMenu {
            let selected = selected ?? parent.selectedOption
            let ascending = ascending ?? parent.ascending
            return UIMenu(children: parent.options.enumerated().map { index, option in
                let isSelected = selected == index
                return UIAction(
                    title: option,
                    subtitle: isSelected && parent.canAscend
                        ? NSLocalizedString(ascending ? "ASCENDING" : "DESCENDING") : nil,
                    attributes: .keepsMenuPresented,
                    state: isSelected ? .on : .off
                ) { [weak self] _ in
                    self?.select(index, current: selected, ascending: ascending)
                }
            })
        }

        private func select(_ index: Int, current: Int, ascending: Bool) {
            let nextAscending = parent.canAscend && (current == index ? !ascending : true)
            parent.selectedOption = index
            parent.ascending = nextAscending
            if let interaction = button?.interactions.compactMap({ $0 as? UIContextMenuInteraction }).first {
                let updatedMenu = makeMenu(selected: index, ascending: nextAscending)
                interaction.updateVisibleMenu { _ in updatedMenu }
            }
        }
    }
}

struct SortFilterGroupView: View {
    let filter: AidokuRunner.Filter

    let canAscend: Bool
    let options: [String]
    let defaultValue: AidokuRunner.Filter.SortDefault?

    @Binding var selectedOption: Int
    @Binding var ascending: Bool

    init(
        filter: AidokuRunner.Filter,
        selectedOption: Binding<Int>,
        ascending: Binding<Bool>
    ) {
        self.filter = filter
        self._selectedOption = selectedOption
        self._ascending = ascending

        guard case let .sort(canAscend, options, defaultValue) = filter.value else {
            fatalError("invalid filter type")
        }
        self.canAscend = canAscend
        self.options = options
        self.defaultValue = defaultValue
    }

    var body: some View {
        WrappingHStack(
            options.indices,
            id: \.self
        ) { offset in
            let option = options[offset]
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if selectedOption == offset && canAscend {
                        ascending.toggle()
                    } else {
                        selectedOption = offset
                        ascending = false
                    }
                }
            } label: {
                Text(option)
                    .lineLimit(1)
            }
            .buttonStyle(SortButtonStyle(state: {
                if selectedOption == offset {
                    ascending ? .ascending : .descending
                } else {
                    .normal
                }
            }()))
            .padding([.trailing, .bottom], 8)
        }
        .padding(.top, 2)
    }
}

struct SortButtonStyle: ButtonStyle {
    var state: State

    enum State {
        case normal
        case descending
        case ascending
    }

    func makeBody(configuration: Configuration) -> some View {
        let foregroundColor = state == .normal ? Color.primary : Color.white
        let backgroundColor = switch state {
            case .normal:
                Color(uiColor: .secondarySystemBackground)
            case .descending, .ascending:
                Color.accentColor
        }
        return HStack(spacing: 5) {
            configuration.label
                .font(.callout)
            if state != .normal {
                Image(systemName: state == .descending ? "chevron.down" : "chevron.up")
                    .font(.callout.weight(.medium))
                    .padding(state == .descending ? .top : .bottom, 1)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 12)
        .foregroundStyle(foregroundColor.opacity(configuration.isPressed ? 0.7 : 1))
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
