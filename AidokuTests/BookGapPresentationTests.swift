import AidokuRunner
import Testing
@testable import Aidoku

@Suite(.serialized) struct BookGapPresentationTests {
    @Test func combinedEpisodeListCountsAllCoveredEpisodes() {
        AppSettings.general.recognizeCombinedBooks.set(true)
        defer { AppSettings.general.recognizeCombinedBooks.reset() }
        // Komga's book numbering mode stores the visible BOOK number as volumeNumber.
        let combined = book(number: 212, title: "Ep. 212 + 213")
        let next = book(number: 214, title: "Ep. 214")

        #expect(BookGapPresentation.missingCount(between: combined, and: next) == 0)
        #expect(BookGapPresentation.missingCount(between: next, and: combined) == 0)
        #expect(BookGapPresentation.totalMissingCount(in: [combined, next]) == 0)
    }

    @Test func explicitCombinedEpisodeRangeCountsAllCoveredEpisodes() {
        AppSettings.general.recognizeCombinedBooks.set(true)
        defer { AppSettings.general.recognizeCombinedBooks.reset() }
        let combined = chapter(number: 212, title: "Episode 212–214")
        let next = chapter(number: 215, title: "Episode 215")

        #expect(BookGapPresentation.missingCount(between: combined, and: next) == 0)
    }

    @Test func ordinaryGapRemainsVisible() {
        let first = chapter(number: 212, title: "Episode 212")
        let next = chapter(number: 214, title: "Episode 214")

        #expect(BookGapPresentation.missingCount(between: first, and: next) == 1)
    }

    @Test func chapterNumberModeAlsoCountsCombinedEpisodes() {
        AppSettings.general.recognizeCombinedBooks.set(true)
        defer { AppSettings.general.recognizeCombinedBooks.reset() }
        let combined = chapter(number: 212, title: "Ep. 212 + 213")
        let next = chapter(number: 214, title: "Ep. 214")

        #expect(BookGapPresentation.missingCount(between: combined, and: next) == 0)
    }

    @Test func eitherNeighborCanCoverTheGap() {
        AppSettings.general.recognizeCombinedBooks.set(true)
        defer { AppSettings.general.recognizeCombinedBooks.reset() }
        let previous = book(number: 212, title: "Ep. 212")
        let combinedNext = book(number: 214, title: "Ep. 213 + 214")

        #expect(BookGapPresentation.missingCount(between: previous, and: combinedNext) == 0)
        #expect(BookGapPresentation.missingCount(between: combinedNext, and: previous) == 0)
    }

    @Test func titlesWithoutEpisodeNumbersDoNotChangeTheGap() {
        let first = book(number: 212, title: "The Beginning")
        let next = book(number: 214, title: "The Return")

        #expect(BookGapPresentation.missingCount(between: first, and: next) == 1)
    }

    @Test func onlyExplicitlyCoveredNumbersAreRemovedFromTheGap() {
        AppSettings.general.recognizeCombinedBooks.set(true)
        defer { AppSettings.general.recognizeCombinedBooks.reset() }
        let combined = book(number: 212, title: "Ep. 212 + 213")
        let next = book(number: 216, title: "Ep. 216")

        #expect(BookGapPresentation.missingCount(between: combined, and: next) == 2)
    }

    @Test func nonconsecutivePlusNotationDoesNotHideGap() {
        AppSettings.general.recognizeCombinedBooks.set(true)
        defer { AppSettings.general.recognizeCombinedBooks.reset() }
        let combined = chapter(number: 212, title: "Episode 212 + 215")
        let next = chapter(number: 216, title: "Episode 216")

        #expect(BookGapPresentation.missingCount(between: combined, and: next) == 3)
    }

    @Test func combinedRecognitionDefaultsToOriginalGapCount() {
        AppSettings.general.recognizeCombinedBooks.set(false)
        defer { AppSettings.general.recognizeCombinedBooks.reset() }
        let combined = book(number: 212, title: "Ep. 212 + 213")
        let next = book(number: 214, title: "Ep. 214")

        #expect(BookGapPresentation.missingCount(between: combined, and: next) == 1)
    }

    private func chapter(number: Float, title: String) -> AidokuRunner.Chapter {
        .init(key: title, title: title, chapterNumber: number)
    }

    private func book(number: Float, title: String) -> AidokuRunner.Chapter {
        .init(key: title, title: title, volumeNumber: number)
    }
}
