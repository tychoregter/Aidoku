import AidokuRunner
import Testing
@testable import Aidoku

@Suite(.serialized) struct ChapterNamingTests {
    @Test func prefixUsesSourceBookNumberAndCanBeReset() {
        let mangaId = MangaIdentifier(sourceKey: "test", mangaKey: "chapter-naming")
        let chapter = AidokuRunner.Chapter(key: "44", title: "Chapter 44", volumeNumber: 44)
        let labsKey = AppSettings.general.labsFeatures
        let previousValue = labsKey.get()
        labsKey.set(true)
        defer {
            ChapterNaming.setPrefix(nil, for: mangaId)
            labsKey.set(previousValue)
        }

        #expect(ChapterNaming.title(for: chapter, in: mangaId) == "Chapter 44")
        ChapterNaming.setPrefix(" Night ", for: mangaId)
        #expect(ChapterNaming.title(for: chapter, in: mangaId) == "Night 44")
        #expect(chapter.title == "Chapter 44")
        ChapterNaming.setPrefix(nil, for: mangaId)
        #expect(ChapterNaming.title(for: chapter, in: mangaId) == "Chapter 44")
    }

    @Test func fractionalAndUnnumberedBooks() {
        let mangaId = MangaIdentifier(sourceKey: "test", mangaKey: "chapter-naming-fractional")
        let labsKey = AppSettings.general.labsFeatures
        let previousValue = labsKey.get()
        labsKey.set(true)
        defer {
            ChapterNaming.setPrefix(nil, for: mangaId)
            labsKey.set(previousValue)
        }
        ChapterNaming.setPrefix("Night", for: mangaId)

        let numbered = AidokuRunner.Chapter(key: "44.1", title: "Chapter 44.1", chapterNumber: 44.1)
        let unnumbered = AidokuRunner.Chapter(key: "special", title: "Special")
        #expect(ChapterNaming.title(for: numbered, in: mangaId) == "Night 44.1")
        #expect(ChapterNaming.title(for: unnumbered, in: mangaId) == "Special")
    }

    @Test func storedNameIsHiddenWhenLabsIsOff() {
        let mangaId = MangaIdentifier(sourceKey: "test", mangaKey: "chapter-naming-labs")
        let chapter = AidokuRunner.Chapter(key: "44", title: "Chapter 44", volumeNumber: 44)
        let labsKey = AppSettings.general.labsFeatures
        let previousValue = labsKey.get()
        defer {
            ChapterNaming.setPrefix(nil, for: mangaId)
            labsKey.set(previousValue)
        }

        labsKey.set(true)
        ChapterNaming.setPrefix("Night", for: mangaId)
        #expect(ChapterNaming.title(for: chapter, in: mangaId) == "Night 44")
        labsKey.set(false)
        #expect(ChapterNaming.prefix(for: mangaId) == nil)
        #expect(ChapterNaming.storedPrefix(for: mangaId) == "Night")
        #expect(ChapterNaming.title(for: chapter, in: mangaId) == "Chapter 44")
        labsKey.set(true)
        #expect(ChapterNaming.title(for: chapter, in: mangaId) == "Night 44")
    }
}
