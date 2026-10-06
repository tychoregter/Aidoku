// Cover-derived colors shared by UIKit cells, SwiftUI covers and manga details.

import AidokuRunner
import Foundation
import SwiftUI
import UIKit

@MainActor
enum CoverPalette {
    enum SamplingPriority: Int {
        case normal
        case hiddenCover
        case infoView

        var queuePriority: Operation.QueuePriority {
            switch self {
            case .normal: .normal
            case .hiddenCover: .high
            case .infoView: .veryHigh
            }
        }

        var qualityOfService: QualityOfService {
            switch self {
            case .normal: .utility
            case .hiddenCover: .utility
            case .infoView: .userInitiated
            }
        }
    }

    // Increment whenever the picker or any derived color formula changes.
    private static let version = 32
    static let customColorDidChange = Notification.Name("CoverPalette.customColorDidChange")
    private static let customColorsKey = "CoverPalette.customBaseColors"
    private static let fileURL = FileManager.default.applicationSupportDirectory
        .appendingPathComponent("CoverPalette.json")
    private static let writeQueue = DispatchQueue(label: "Aidoku.CoverPalette.disk", qos: .utility)
    private static let samplingQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Aidoku.CoverPalette.sampling"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 2
        return queue
    }()

    private struct RGB: Codable, Equatable {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        init(_ color: UIColor) {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            self.red = Double(red)
            self.green = Double(green)
            self.blue = Double(blue)
            self.alpha = Double(alpha)
        }

        var color: UIColor {
            UIColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
        }
    }

    private struct Colors: Codable {
        let base: RGB
        let headerLight: RGB
        let headerDark: RGB
        let headerBottomLight: RGB
        let headerBottomDark: RGB
        let controlLight: RGB
        let controlDark: RGB
        let hiddenLight: RGB
        let hiddenDark: RGB
        let hiddenForegroundLight: RGB
        let hiddenForegroundDark: RGB
        let darkHeaderTextLight: Bool
        let darkHeaderTextDark: Bool

        @MainActor init(base color: UIColor) {
            base = RGB(color)
            let light = MangaDetailsBackdrop.darkenedBackgroundColor(from: color, colorScheme: .light)
            let dark = MangaDetailsBackdrop.darkenedBackgroundColor(from: color, colorScheme: .dark)
            headerLight = RGB(light)
            headerDark = RGB(dark)
            headerBottomLight = RGB(MangaDetailsBackdrop.bottomGradientColor(from: light))
            headerBottomDark = RGB(MangaDetailsBackdrop.bottomGradientColor(from: dark))
            darkHeaderTextLight = MangaDetailsBackdrop.shouldUseDarkHeaderText(color, colorScheme: .light)
            darkHeaderTextDark = MangaDetailsBackdrop.shouldUseDarkHeaderText(color, colorScheme: .dark)
            controlLight = RGB(MangaDetailsBackdrop.controlBackgroundColor(
                from: color, colorScheme: .light, usesDarkText: darkHeaderTextLight
            ))
            controlDark = RGB(MangaDetailsBackdrop.controlBackgroundColor(
                from: color, colorScheme: .dark, usesDarkText: darkHeaderTextDark
            ))
            let hiddenLightColor = NSFWCoverView.backgroundColor(for: color, isDark: false)
            let hiddenDarkColor = NSFWCoverView.backgroundColor(for: color, isDark: true)
            hiddenLight = RGB(hiddenLightColor)
            hiddenDark = RGB(hiddenDarkColor)
            hiddenForegroundLight = RGB(NSFWCoverView.foregroundColor(for: hiddenLightColor))
            hiddenForegroundDark = RGB(NSFWCoverView.foregroundColor(for: hiddenDarkColor))
        }

        func header(dark: Bool) -> UIColor { (dark ? headerDark : headerLight).color }
        func headerBottom(dark: Bool) -> UIColor { (dark ? headerBottomDark : headerBottomLight).color }
        func control(dark: Bool) -> UIColor { (dark ? controlDark : controlLight).color }
        func hidden(dark: Bool) -> UIColor { (dark ? hiddenDark : hiddenLight).color }
        func hiddenForeground(dark: Bool) -> UIColor {
            (dark ? hiddenForegroundDark : hiddenForegroundLight).color
        }
        func darkHeaderText(dark: Bool) -> Bool { dark ? darkHeaderTextDark : darkHeaderTextLight }
    }

    private struct Record: Codable {
        let sourceKey: String
        let mangaKey: String
        let url: String
        let fingerprint: UInt64
        let colors: Colors

        var identifier: MangaIdentifier {
            MangaIdentifier(sourceKey: sourceKey, mangaKey: mangaKey)
        }
    }

    private struct Archive: Codable {
        let version: Int
        let records: [String: Record]
    }

    private final class Box {
        let colors: Colors
        let fingerprint: UInt64
        init(colors: Colors, fingerprint: UInt64) {
            self.colors = colors
            self.fingerprint = fingerprint
        }
    }

    private final class WeakImage {
        weak var image: UIImage?
        init(_ image: UIImage) { self.image = image }
    }

    private struct Pending {
        let imageID: ObjectIdentifier
        var callbacks: [(UIColor) -> Void]
        var identifiers: Set<MangaIdentifier>
        var priority: SamplingPriority
        var operation: BlockOperation?
    }

    @MainActor private final class State {
        let memory = NSCache<NSString, Box>()
        var records: [String: Record] = [:]
        var activeImages: [String: WeakImage] = [:]
        var observedURLByID: [String: String] = [:]
        var inFlight: [String: Pending] = [:]
        var generations: [String: UInt64] = [:]
        var epoch: UInt64 = 0
        var pendingWrite: DispatchWorkItem?
        var customColors: [String: String] = UserDefaults.standard.dictionary(forKey: customColorsKey) as? [String: String] ?? [:]
        var derivedCustomColors: [String: Colors] = [:]

        init() {
            if let data = try? Data(contentsOf: fileURL),
               let archive = try? JSONDecoder().decode(Archive.self, from: data),
               archive.version == version {
                records = archive.records
                for record in records.values {
                    memory.setObject(Box(colors: record.colors, fingerprint: record.fingerprint),
                                     forKey: record.url as NSString)
                }
            } else if FileManager.default.fileExists(atPath: fileURL.path) {
                // A picker revision must never reuse colors derived by older rules.
                let url = fileURL
                writeQueue.async { try? FileManager.default.removeItem(at: url) }
            }
        }

        func colors(for url: String) -> Colors? {
            if let colors = memory.object(forKey: url as NSString)?.colors { return colors }
            guard let record = records.values.first(where: { $0.url == url }) else { return nil }
            memory.setObject(Box(colors: record.colors, fingerprint: record.fingerprint),
                             forKey: url as NSString)
            return record.colors
        }
    }

    private static let state = State()

    private static var retainsNonLibraryReading: Bool {
        LibraryViewModel.isDedicatedContinueReadingEnabled
            && AppSettings.library.continueReadingIncludeNonLibraryTitles.get()
    }

    private static func colors(for url: String, identifier: MangaIdentifier?) -> Colors? {
        if let identifier, let custom = customColors(for: identifier) { return custom }
        return state.colors(for: url)
    }

    private static func customColors(for identifier: MangaIdentifier) -> Colors? {
        let key = identifier.description
        if let colors = state.derivedCustomColors[key] { return colors }
        guard let hex = state.customColors[key], let color = color(fromHex: hex) else { return nil }
        let colors = Colors(base: color)
        state.derivedCustomColors[key] = colors
        return colors
    }

    static func customColor(for identifier: MangaIdentifier) -> UIColor? {
        guard let hex = state.customColors[identifier.description] else { return nil }
        return color(fromHex: hex)
    }

    static func customColorsForBackup() -> [String: String] {
        state.customColors
    }

    static func restoreCustomColors(_ colors: [String: String], validIdentifiers: Set<MangaIdentifier>) {
        let validKeys = Set(validIdentifiers.map(\.description))
        state.customColors = colors.filter { validKeys.contains($0.key) }
        state.derivedCustomColors.removeAll()
        UserDefaults.standard.set(state.customColors, forKey: customColorsKey)
        for identifier in validIdentifiers {
            NotificationCenter.default.post(name: customColorDidChange, object: identifier)
        }
    }

    static func setCustomColor(_ color: UIColor?, for identifier: MangaIdentifier) {
        let key = identifier.description
        if let color, let hex = hexString(for: color) {
            state.customColors[key] = hex
        } else {
            state.customColors.removeValue(forKey: key)
        }
        state.derivedCustomColors.removeValue(forKey: key)
        UserDefaults.standard.set(state.customColors, forKey: customColorsKey)
        NotificationCenter.default.post(name: customColorDidChange, object: identifier)
    }

    static func color(fromHex text: String) -> UIColor? {
        let hex = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return UIColor(red: CGFloat((value >> 16) & 0xff) / 255,
                       green: CGFloat((value >> 8) & 0xff) / 255,
                       blue: CGFloat(value & 0xff) / 255, alpha: 1)
    }

    static func hexString(for color: UIColor) -> String? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return String(format: "#%02X%02X%02X", Int((red * 255).rounded()),
                      Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    static func color(for url: String, identifier: MangaIdentifier? = nil) -> UIColor? {
        colors(for: url, identifier: identifier)?.base.color
    }
    static func headerColor(for url: String, dark: Bool, identifier: MangaIdentifier? = nil) -> UIColor? {
        colors(for: url, identifier: identifier)?.header(dark: dark)
    }
    static func headerBottomColor(for url: String, dark: Bool, identifier: MangaIdentifier? = nil) -> UIColor? {
        colors(for: url, identifier: identifier)?.headerBottom(dark: dark)
    }
    static func controlColor(for url: String, dark: Bool, identifier: MangaIdentifier? = nil) -> UIColor? {
        colors(for: url, identifier: identifier)?.control(dark: dark)
    }
    static func usesDarkHeaderText(for url: String, dark: Bool, identifier: MangaIdentifier? = nil) -> Bool? {
        colors(for: url, identifier: identifier)?.darkHeaderText(dark: dark)
    }
    static func hiddenColor(for url: String, dark: Bool, identifier: MangaIdentifier? = nil) -> UIColor? {
        colors(for: url, identifier: identifier)?.hidden(dark: dark)
    }
    static func hiddenForegroundColor(for url: String, dark: Bool, identifier: MangaIdentifier? = nil) -> UIColor? {
        colors(for: url, identifier: identifier)?.hiddenForeground(dark: dark)
    }

    /// Called for every decoded cover, including ordinary visible covers. The
    /// existing color can be displayed immediately while a changed image is checked.
    static func observe(
        _ image: UIImage,
        for url: String,
        identifier: MangaIdentifier? = nil,
        priority: SamplingPriority = .normal,
        onColor: ((UIColor) -> Void)? = nil
    ) {
        guard !url.isEmpty else { return }
        if let identifier { state.observedURLByID[identifier.description] = url }
        if let existing = color(for: url) { onColor?(existing) }
        let imageID = ObjectIdentifier(image)
        if var pending = state.inFlight[url], pending.imageID == imageID {
            if let onColor { pending.callbacks.append(onColor) }
            if let identifier { pending.identifiers.insert(identifier) }
            if priority.rawValue > pending.priority.rawValue {
                pending.priority = priority
                if let operation = pending.operation, !operation.isExecuting {
                    operation.queuePriority = priority.queuePriority
                    operation.qualityOfService = priority.qualityOfService
                }
            }
            state.inFlight[url] = pending
            return
        }
        if state.activeImages[url]?.image === image,
           let box = state.memory.object(forKey: url as NSString) {
            if let identifier,
               !(state.records[identifier.description]?.url == url
                 && state.records[identifier.description]?.fingerprint == box.fingerprint) {
                Task { await retainIfEligible(identifier, url: url,
                                              fingerprint: box.fingerprint, colors: box.colors) }
            }
            return
        }
        state.activeImages[url] = WeakImage(image)
        if let previous = state.inFlight[url] {
            previous.operation?.cancel()
            state.generations[url, default: 0] &+= 1
        }
        let generation = state.generations[url, default: 0]
        let epoch = state.epoch
        let operation = BlockOperation {
            let sample = image.dominantColorSample()
            Task { @MainActor in
                guard generation == state.generations[url, default: 0], epoch == state.epoch,
                      let sample else { return }
                let pending = state.inFlight.removeValue(forKey: url)
                let previous = state.memory.object(forKey: url as NSString)
                if previous?.fingerprint != sample.fingerprint {
                    let colors = Colors(base: sample.color)
                    state.memory.setObject(Box(colors: colors, fingerprint: sample.fingerprint),
                                           forKey: url as NSString)
                    // A server may replace an image without changing its URL.
                    let matchingKeys = state.records.compactMap { key, record in
                        record.url == url ? key : nil
                    }
                    for key in matchingKeys {
                        guard let record = state.records[key] else { continue }
                        state.records[key] = Record(sourceKey: record.sourceKey, mangaKey: record.mangaKey,
                                                    url: url, fingerprint: sample.fingerprint, colors: colors)
                    }
                    if !matchingKeys.isEmpty { scheduleWrite() }
                }
                let colors = state.colors(for: url) ?? Colors(base: sample.color)
                if previous?.colors.base != colors.base {
                    pending?.callbacks.forEach { $0(colors.base.color) }
                }
                for identifier in pending?.identifiers ?? [] {
                    Task { await retainIfEligible(identifier, url: url, fingerprint: sample.fingerprint, colors: colors) }
                }
            }
        }
        operation.queuePriority = priority.queuePriority
        operation.qualityOfService = priority.qualityOfService
        state.inFlight[url] = Pending(
            imageID: imageID,
            callbacks: onColor.map { [$0] } ?? [],
            identifiers: identifier.map { [$0] } ?? [],
            priority: priority,
            operation: operation
        )
        samplingQueue.addOperation(operation)
    }

    private static func retainIfEligible(
        _ identifier: MangaIdentifier, url: String, fingerprint: UInt64, colors: Colors
    ) async {
        if state.records[identifier.description]?.url == url,
           state.records[identifier.description]?.fingerprint == fingerprint { return }
        let includeReading = retainsNonLibraryReading
        let eligible = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.hasLibraryManga(mangaId: identifier, context: context)
                || (includeReading && CoreDataManager.shared.hasHistory(mangaId: identifier, context: context))
        }
        guard eligible, state.memory.object(forKey: url as NSString)?.fingerprint == fingerprint else { return }
        let key = identifier.description
        if let old = state.records[key], old.url != url {
            state.memory.removeObject(forKey: old.url as NSString)
            state.activeImages.removeValue(forKey: old.url)
            state.generations[old.url, default: 0] &+= 1
        }
        if state.records[key]?.fingerprint == fingerprint, state.records[key]?.url == url { return }
        state.records[key] = Record(sourceKey: identifier.sourceKey, mangaKey: identifier.mangaKey,
                                    url: url, fingerprint: fingerprint, colors: colors)
        scheduleWrite()
    }

    /// Promotes a cover already loaded in Browse or the reader when its title
    /// enters Library or Continue Reading, without loading the image again.
    static func persistIfEligible(_ identifier: MangaIdentifier) {
        guard let url = state.observedURLByID[identifier.description],
              let box = state.memory.object(forKey: url as NSString) else { return }
        Task { await retainIfEligible(identifier, url: url,
                                      fingerprint: box.fingerprint, colors: box.colors) }
    }

    private static func scheduleWrite(immediately: Bool = false) {
        let snapshot = Archive(version: version, records: state.records)
        let url = fileURL
        state.pendingWrite?.cancel()
        let work = DispatchWorkItem {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
        state.pendingWrite = work
        if immediately {
            writeQueue.async(execute: work)
        } else {
            writeQueue.asyncAfter(deadline: .now() + .milliseconds(200), execute: work)
        }
    }

    static func flush() {
        if state.pendingWrite != nil { scheduleWrite(immediately: true) }
    }

    static func invalidate(_ identifier: MangaIdentifier) {
        state.observedURLByID.removeValue(forKey: identifier.description)
        guard let old = state.records.removeValue(forKey: identifier.description) else { return }
        invalidateMemory(for: old.url)
        scheduleWrite()
    }

    static func invalidate(url: String) {
        let keys = state.records.filter { $0.value.url == url }.map(\.key)
        keys.forEach { state.records.removeValue(forKey: $0) }
        invalidateMemory(for: url)
        if !keys.isEmpty { scheduleWrite() }
    }

    private static func invalidateMemory(for url: String) {
        state.memory.removeObject(forKey: url as NSString)
        state.activeImages.removeValue(forKey: url)
        state.generations[url, default: 0] &+= 1
    }

    static func forgetMemory(for url: String) {
        invalidateMemory(for: url)
    }

    static func reconcile(_ identifier: MangaIdentifier) async {
        let includeReading = retainsNonLibraryReading
        let eligible = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.hasLibraryManga(mangaId: identifier, context: context)
                || (includeReading && CoreDataManager.shared.hasHistory(mangaId: identifier, context: context))
        }
        if !eligible { invalidate(identifier) }
    }

    /// Repairs removals that may have been interrupted while the app was closed.
    static func reconcileAll() async {
        let includeReading = retainsNonLibraryReading
        let eligible = await CoreDataManager.shared.container.performBackgroundTask { context in
            let library = CoreDataManager.shared.getLibraryManga(context: context)
                .compactMap { $0.manga?.identifier.description }
            let history = includeReading ? CoreDataManager.shared.getHistory(context: context)
                .map { $0.identifier.mangaIdentifier.description }
                : []
            return Set(library + history)
        }
        let removed = state.records.filter { !eligible.contains($0.key) }
        for (key, record) in removed {
            state.records.removeValue(forKey: key)
            invalidateMemory(for: record.url)
        }
        if !removed.isEmpty { scheduleWrite() }
    }

    static func clearAll() {
        state.epoch &+= 1
        state.pendingWrite?.cancel()
        state.pendingWrite = nil
        state.inFlight.removeAll()
        state.activeImages.removeAll()
        state.observedURLByID.removeAll()
        state.memory.removeAllObjects()
        state.records.removeAll()
        let url = fileURL
        writeQueue.async { try? FileManager.default.removeItem(at: url) }
    }
}
