//
//  GenreFilterSettingsView.swift
//  Aidoku
//

import SwiftUI

enum GenreFilterText {
    static func localized(_ key: String, fallback: String) -> String {
        Bundle.main.localizedString(forKey: key, value: fallback, table: nil)
    }
}

struct GenreFilterSettingsView: View {
    @State private var genres: [String] = []
    @State private var configuration = LibraryGenreFilterSettings.load()
    @State private var isLoading = true
    @State private var showingLinkSheet = false
    @State private var linkSheetPrimaryGenre: String?

    private var linkedGenreGroups: [LinkedGenreGroup] {
        Dictionary(grouping: configuration.links.keys) { aliasID in
            LibraryGenreFilterSettings.rootIdentifier(for: aliasID, configuration: configuration)
        }
        .map { primaryID, aliasIDs in
            LinkedGenreGroup(
                primaryID: primaryID,
                aliasIDs: aliasIDs.sorted {
                    displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending
                }
            )
        }
        .sorted {
            displayName(for: $0.primaryID)
                .localizedCaseInsensitiveCompare(displayName(for: $1.primaryID)) == .orderedAscending
        }
    }

    var body: some View {
        List {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } else if genres.isEmpty {
                ContentUnavailableView(
                    GenreFilterText.localized("GENRE", fallback: "Genres"),
                    systemImage: "tag",
                    description: Text(
                        GenreFilterText.localized("NO_LIBRARY_GENRES", fallback: "No library genres found.")
                    )
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(genres, id: \.self) { genre in
                        genreToggle(genre)
                    }
                } header: {
                    Text(
                        GenreFilterText.localized("AVAILABLE_GENRES", fallback: "Shown Genres")
                    )
                } footer: {
                    Text(
                        GenreFilterText.localized(
                            "GENRE_FILTER_SETTINGS_INFO",
                            fallback: "Enabled genres appear in the Library filter."
                        )
                    )
                }

                Section {
                    if linkedGenreGroups.isEmpty {
                        Text(
                            GenreFilterText.localized("NO_LINKED_GENRES", fallback: "No links")
                        )
                        .foregroundStyle(.secondary)
                    } else {
                        ForEach(linkedGenreGroups) { group in
                            Button {
                                edit(group)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(displayName(for: group.primaryID))
                                            .foregroundStyle(.primary)
                                        Text(group.aliasIDs.map(displayName).joined(separator: ", "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .foregroundStyle(.primary)
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    edit(group)
                                } label: {
                                    Label(NSLocalizedString("EDIT"), systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    delete(group)
                                } label: {
                                    Label(NSLocalizedString("DELETE"), systemImage: "trash")
                                }
                            }
                        }
                    }

                    Button {
                        linkSheetPrimaryGenre = nil
                        showingLinkSheet = true
                    } label: {
                        Label(
                            GenreFilterText.localized("ADD_GENRE_LINK", fallback: "Add Link"),
                            systemImage: "link.badge.plus"
                        )
                    }
                } header: {
                    Text(
                        GenreFilterText.localized("LINKED_GENRES", fallback: "Linked Genres")
                    )
                } footer: {
                    Text(
                        GenreFilterText.localized(
                            "LINKED_GENRES_INFO",
                            fallback: "Group equivalent names under one filter."
                        )
                    )
                }
            }
        }
        .navigationTitle(
            GenreFilterText.localized("GENRE_FILTER", fallback: "Genre Filters")
        )
        .task {
            await loadGenres()
        }
        .onChange(of: configuration) { _, configuration in
            LibraryGenreFilterSettings.save(configuration)
            NotificationCenter.default.post(name: .genreFilterSettingsChanged, object: nil)
        }
        .sheet(isPresented: $showingLinkSheet) {
            GenreLinkSheet(
                genres: genres,
                configuration: $configuration,
                initialPrimaryGenre: linkSheetPrimaryGenre
            )
        }
    }

    private func edit(_ group: LinkedGenreGroup) {
        linkSheetPrimaryGenre = displayName(for: group.primaryID)
        showingLinkSheet = true
    }

    private func delete(_ group: LinkedGenreGroup) {
        for aliasID in group.aliasIDs {
            configuration.links.removeValue(forKey: aliasID)
        }
    }

    private func genreToggle(_ genre: String) -> some View {
        let linkedTarget = LibraryGenreFilterSettings.linkedTarget(
            for: genre,
            availableNames: genres,
            configuration: configuration
        )
        return Toggle(
            isOn: Binding(
                get: {
                    LibraryGenreFilterSettings.isEnabled(genre, configuration: configuration)
                },
                set: { enabled in
                    LibraryGenreFilterSettings.setEnabled(
                        enabled,
                        for: genre,
                        configuration: &configuration
                    )
                }
            )
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(genre)
                if let linkedTarget {
                    Text(
                        String(
                            format: GenreFilterText.localized("LINKED_TO_%@", fallback: "Linked to %@"),
                            linkedTarget
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(linkedTarget != nil)
    }

    private func displayName(for identifier: String) -> String {
        LibraryGenreFilterSettings.displayName(for: identifier, availableNames: genres)
    }

    private func loadGenres() async {
        let values: [String] = await CoreDataManager.shared.container.performBackgroundTask { context in
            let request = LibraryMangaObject.fetchRequest()
            request.predicate = NSPredicate(format: "manga != nil")
            let libraryObjects = (try? context.fetch(request)) ?? []
            return libraryObjects.reduce(into: [String]()) { values, libraryObject in
                guard let manga = libraryObject.manga else { return }
                if manga.sourceId.hasPrefix(KomgaSourceRunner.sourceKeyPrefix) {
                    values.append(contentsOf: KomgaGenreStore.genres(sourceKey: manga.sourceId, mangaKey: manga.id))
                } else {
                    values.append(contentsOf: manga.tags ?? [])
                }
            }
        }
        genres = LibraryGenreFilterSettings.uniqueGenreNames(values)
        isLoading = false
    }
}

private struct LinkedGenreGroup: Identifiable {
    let primaryID: String
    let aliasIDs: [String]

    var id: String { primaryID }
}

private struct GenreLinkSheet: View {
    let genres: [String]
    @Binding var configuration: LibraryGenreFilterConfiguration

    @Environment(\.dismiss) private var dismiss

    @State private var primaryGenre: String
    @State private var linkedGenres: Set<String>

    init(
        genres: [String],
        configuration: Binding<LibraryGenreFilterConfiguration>,
        initialPrimaryGenre: String? = nil
    ) {
        let primaryGenre = initialPrimaryGenre ?? genres.first ?? ""
        self.genres = genres
        self._configuration = configuration
        self._primaryGenre = State(initialValue: primaryGenre)
        self._linkedGenres = State(
            initialValue: Set(
                genres.filter {
                    LibraryGenreFilterSettings.isLinked(
                        $0,
                        to: primaryGenre,
                        configuration: configuration.wrappedValue
                    )
                }
            )
        )
    }

    private var linkableGenres: [String] {
        genres.filter {
            LibraryGenreFilterSettings.normalize($0) != LibraryGenreFilterSettings.normalize(primaryGenre)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(
                    GenreFilterText.localized("PRIMARY_GENRE", fallback: "Filter Name")
                ) {
                    Picker(
                        GenreFilterText.localized("SHOW_AS", fallback: "Show As"),
                        selection: $primaryGenre
                    ) {
                        ForEach(genres, id: \.self) { genre in
                            Text(genre).tag(genre)
                        }
                    }
                }

                Section {
                    ForEach(linkableGenres, id: \.self) { genre in
                        Button {
                            if !linkedGenres.insert(genre).inserted {
                                linkedGenres.remove(genre)
                            }
                        } label: {
                            HStack {
                                Text(genre)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if linkedGenres.contains(genre) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } header: {
                    Text(
                        GenreFilterText.localized("ALSO_MATCH", fallback: "Also Match")
                    )
                } footer: {
                    Text(
                        GenreFilterText.localized("LINK_GENRES_INFO", fallback: "Select equivalent names.")
                    )
                }
            }
            .navigationTitle(
                GenreFilterText.localized("LINK_GENRES", fallback: "Link Genres")
            )
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: primaryGenre) { _, primaryGenre in
                linkedGenres = Set(
                    genres.filter {
                        LibraryGenreFilterSettings.isLinked(
                            $0,
                            to: primaryGenre,
                            configuration: configuration
                        )
                    }
                )
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("CANCEL")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("DONE")) {
                        saveLinks()
                        dismiss()
                    }
                    .disabled(primaryGenre.isEmpty)
                }
            }
        }
    }

    private func saveLinks() {
        var updatedConfiguration = configuration
        let existingLinks = genres.filter {
            LibraryGenreFilterSettings.isLinked(
                $0,
                to: primaryGenre,
                configuration: updatedConfiguration
            )
        }
        for genre in existingLinks {
            LibraryGenreFilterSettings.unlink(genre, configuration: &updatedConfiguration)
        }
        for genre in linkedGenres {
            LibraryGenreFilterSettings.link(
                genre,
                to: primaryGenre,
                configuration: &updatedConfiguration
            )
        }
        configuration = updatedConfiguration
    }
}
