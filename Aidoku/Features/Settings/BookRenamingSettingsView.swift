//
//  BookRenamingSettingsView.swift
//  Aidoku
//

import SwiftUI

/// Shared by the Books header and Labs settings so both entry points edit the
/// same stored prefix with the same controls.
struct BookRenameRequest {
    let mangaId: MangaIdentifier
    var name: String
    let hadCustomName: Bool

    init(_ mangaId: MangaIdentifier) {
        self.mangaId = mangaId
        self.name = ChapterNaming.storedPrefix(for: mangaId) ?? ""
        self.hadCustomName = !name.isEmpty
    }
}

struct BookRenameEditor: ViewModifier {
    @Binding var request: BookRenameRequest?

    func body(content: Content) -> some View {
        content.alert(
                NSLocalizedString("CUSTOM_BOOK_NAME", value: "Rename Books", comment: "Title of the custom numbered book naming editor"),
                isPresented: Binding(
                    get: { request != nil },
                    set: { if !$0 { request = nil } }
                )
            ) {
                TextField(NSLocalizedString("BOOK_NAME_PREFIX", value: "Chapter", comment: "Custom word before a book number"), text: Binding(
                    get: { request?.name ?? "" },
                    set: { newName in
                        guard var current = request else { return }
                        current.name = newName
                        request = current
                    }
                ))
                if request?.hadCustomName == true {
                    Button(NSLocalizedString("RESTORE_SOURCE_BOOK_NAMES", value: "Use Source Names", comment: "Restore source book names"), role: .destructive) {
                        guard let request else { return }
                        ChapterNaming.setPrefix(nil, for: request.mangaId)
                    }
                }
                Button(NSLocalizedString("CANCEL"), role: .cancel) {}
                Button(NSLocalizedString("APPLY", value: "Apply", comment: "Apply the custom book name")) {
                    guard let request else { return }
                    ChapterNaming.setPrefix(request.name, for: request.mangaId)
                }
            }
    }
}

struct LabsFeaturesView: View {
    let path: NavigationCoordinator
    @AppStorage("General.labsFeatures") private var bookRenamingEnabled = false
    @AppStorage("General.recognizeCombinedBooks") private var recognizeCombinedBooks = false
    @AppStorage("General.flareSolverrURL") private var flareSolverrURL = ""
    @AppStorage("General.flareSolverrFallback") private var flareSolverrFallback = true

    var body: some View {
        List {
            Section {
                Toggle(NSLocalizedString("BOOK_RENAMING", value: "Book Renaming", comment: "Experimental per-series book naming feature"),
                       isOn: $bookRenamingEnabled)
                if bookRenamingEnabled {
                    NavigationLink(NSLocalizedString("RENAMED_BOOKS", value: "Renamed Books", comment: "Manage custom book names")) {
                        BookRenamingSettingsView(path: path)
                    }
                }
            } header: {
                Text(NSLocalizedString("LABS_MANGA_INFO", value: "Series Info", comment: "Labs settings related to series information"))
            }
            Section {
                Toggle(NSLocalizedString("RECOGNIZE_COMBINED_BOOKS", value: "Recognize Combined Books", comment: "Recognize multi-episode books when checking for missing books"),
                       isOn: $recognizeCombinedBooks)
            }
            Section {
                TextField(NSLocalizedString("FLARESOLVERR_URL"), text: $flareSolverrURL, prompt: Text("http://127.0.0.1:8191"))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !flareSolverrURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Toggle(NSLocalizedString("FLARESOLVERR_FALLBACK"), isOn: $flareSolverrFallback)
                }
            } header: {
                Text(NSLocalizedString("FLARESOLVERR"))
            } footer: {
                Text(NSLocalizedString("FLARESOLVERR_TEXT"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("LABS_FEATURES"))
        .onChange(of: bookRenamingEnabled) { _ in
            // A nil object means every displayed series should return to its
            // source title or restore its previously saved custom name.
            NotificationCenter.default.post(name: ChapterNaming.didChange, object: nil)
        }
    }
}

private struct BookRenameManga: Identifiable, Sendable {
    let id: MangaIdentifier
    let title: String
}

private struct BookRenamingSettingsView: View {
    let path: NavigationCoordinator

    @State private var allManga: [BookRenameManga] = []
    @State private var libraryManga: [BookRenameManga] = []
    @State private var revision = 0
    @State private var renameRequest: BookRenameRequest?
    @State private var pendingAddedManga: MangaIdentifier?
    @State private var showingLibraryPicker = false

    private var renamedManga: [BookRenameManga] {
        allManga.filter { ChapterNaming.storedPrefix(for: $0.id) != nil }
    }

    var body: some View {
        let _ = revision
        return List {
            if renamedManga.isEmpty {
                Text(NSLocalizedString("NO_RENAMED_BOOKS", value: "No renamed books yet.", comment: "Empty custom book naming list"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(renamedManga) { manga in
                    Button {
                        openInfo(for: manga.id)
                    } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(manga.title)
                                    .foregroundStyle(Color(uiColor: .label))
                                Text("→ \(ChapterNaming.storedPrefix(for: manga.id) ?? "")")
                                    .font(.subheadline)
                                    .foregroundStyle(Color(uiColor: .label).opacity(0.6))
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            ChapterNaming.setPrefix(nil, for: manga.id)
                        } label: {
                            Label(NSLocalizedString("DELETE"), systemImage: "trash")
                        }
                        Button {
                            renameRequest = BookRenameRequest(manga.id)
                        } label: {
                            Label(NSLocalizedString("EDIT"), systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("RENAMED_BOOKS"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingLibraryPicker = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(NSLocalizedString("ADD_BOOK_RENAME", value: "Add Book Rename", comment: "Choose a library series to rename its books"))
            }
        }
        .sheet(isPresented: $showingLibraryPicker, onDismiss: {
            if let pendingAddedManga {
                renameRequest = BookRenameRequest(pendingAddedManga)
                self.pendingAddedManga = nil
            }
        }) {
            BookRenameLibraryPicker(manga: libraryManga) { selected in
                pendingAddedManga = selected
                showingLibraryPicker = false
            }
        }
        .modifier(BookRenameEditor(request: $renameRequest))
        .task { await loadManga() }
        .onReceive(NotificationCenter.default.publisher(for: ChapterNaming.didChange)) { _ in
            revision &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateLibrary)) { _ in
            Task { await loadManga() }
        }
    }

    private func openInfo(for identifier: MangaIdentifier) {
        guard let manga = CoreDataManager.shared.getManga(mangaId: identifier) else { return }
        path.push(MangaViewController(manga: manga.toNewManga(), parent: path.rootViewController))
    }

    private func loadManga() async {
        let (all, library) = await CoreDataManager.shared.container.performBackgroundTask { context in
            let all = CoreDataManager.shared.getManga(context: context).map {
                BookRenameManga(id: $0.identifier, title: $0.title)
            }
            let library = CoreDataManager.shared.getLibraryManga(context: context).compactMap { object in
                object.manga.map { BookRenameManga(id: $0.identifier, title: $0.title) }
            }
            return (all, library)
        }
        allManga = all.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        libraryManga = library.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}

private struct BookRenameLibraryPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    let manga: [BookRenameManga]
    let onSelect: (MangaIdentifier) -> Void

    private var filteredManga: [BookRenameManga] {
        searchText.isEmpty ? manga : manga.filter { $0.title.localizedStandardContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List(filteredManga) { item in
                Button(item.title) { onSelect(item.id) }
                    .foregroundStyle(.primary)
            }
            .searchable(text: $searchText)
            .navigationTitle(NSLocalizedString("ADD_BOOK_RENAME"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("CANCEL")) { dismiss() }
                }
            }
        }
    }
}
