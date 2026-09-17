//
//  WebtoonPageDimensionCache.swift
//  Aidoku
//

import AidokuRunner
import Foundation
import ImageIO
import UIKit

actor WebtoonPageDimensionCache {
    static let shared = WebtoonPageDimensionCache()

    struct Dimensions: Codable, Sendable {
        let width: CGFloat
        let height: CGFloat

        var ratio: CGFloat? {
            guard width > 0, height > 0 else { return nil }
            return height / width
        }
    }

    private static let cacheURL = FileManager.default.cachesDirectory
        .appendingPathComponent("webtoon-page-dimensions.json")

    private var values: [String: Dimensions] = [:]
    private var hasLoaded = false
    private var saveTask: Task<Void, Never>?

    static func key(
        sourceKey: String,
        mangaKey: String,
        chapterKey: String,
        pageIndex: Int
    ) -> String {
        [sourceKey, mangaKey, chapterKey, String(pageIndex)]
            .joined(separator: "\u{1F}")
    }

    func ratios(for keys: [String]) -> [String: CGFloat] {
        loadIfNeeded()
        return keys.reduce(into: [:]) { result, key in
            if let ratio = values[key]?.ratio {
                result[key] = ratio
            }
        }
    }

    func ratio(for key: String) -> CGFloat? {
        loadIfNeeded()
        return values[key]?.ratio
    }

    func store(size: CGSize, for key: String) {
        guard size.width > 0, size.height > 0 else { return }
        loadIfNeeded()
        let dimensions = Dimensions(width: size.width, height: size.height)
        guard values[key] != dimensions else { return }
        values[key] = dimensions
        scheduleSave()
    }

    func removeAll() {
        saveTask?.cancel()
        saveTask = nil
        values.removeAll()
        hasLoaded = true
        try? FileManager.default.removeItem(at: Self.cacheURL)
    }

    private func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        guard
            let data = try? Data(contentsOf: Self.cacheURL),
            let decoded = try? JSONDecoder().decode([String: Dimensions].self, from: data)
        else { return }
        values = decoded
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            await self.save()
        }
    }

    private func save() {
        saveTask = nil
        guard let data = try? JSONEncoder().encode(values) else { return }
        try? data.write(to: Self.cacheURL, options: .atomic)
    }
}

extension WebtoonPageDimensionCache.Dimensions: Equatable {}

/// Reads only enough of a remote image response for ImageIO to expose its
/// pixel dimensions. The request is cancelled as soon as metadata is found.
final class WebtoonPageDimensionLoader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private static let byteLimit = 512 * 1024

    private let imageSource = CGImageSourceCreateIncremental(nil)
    private let stateLock = NSLock()
    private var receivedData = Data()
    private var continuation: CheckedContinuation<CGSize?, Never>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var finished = false

    static func dimensions(
        for page: Page,
        source: AidokuRunner.Source?
    ) async -> CGSize? {
        if let image = page.image, image.size.width > 0, image.size.height > 0 {
            return image.size
        }
        if let base64 = page.base64,
           let data = Data(base64Encoded: base64),
           let size = imageDimensions(from: data) {
            return size
        }
        guard let urlString = page.imageURL, let url = URL(string: urlString) else {
            return nil
        }
        if url.isFileURL {
            guard
                let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil)
                    as? [CFString: Any]
            else { return nil }
            return imageDimensions(from: properties)
        }

        var request = if let source {
            await source.getModifiedImageRequest(url: url, context: page.context)
        } else {
            URLRequest(url: url)
        }
        request.setValue("bytes=0-\(byteLimit - 1)", forHTTPHeaderField: "Range")
        request.timeoutInterval = 20
        return await WebtoonPageDimensionLoader().load(request: request)
    }

    private func load(request: URLRequest) async -> CGSize? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                stateLock.lock()
                guard !finished else {
                    stateLock.unlock()
                    continuation.resume(returning: nil)
                    return
                }
                self.continuation = continuation
                stateLock.unlock()

                let configuration = URLSessionConfiguration.default
                configuration.requestCachePolicy = .returnCacheDataElseLoad
                let queue = OperationQueue()
                queue.maxConcurrentOperationCount = 1
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
                let task = session.dataTask(with: request)

                stateLock.lock()
                guard !finished else {
                    stateLock.unlock()
                    session.invalidateAndCancel()
                    return
                }
                self.session = session
                self.task = task
                stateLock.unlock()
                task.resume()
            }
        } onCancel: {
            self.finish(with: nil)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let response = response as? HTTPURLResponse,
           !(200...299).contains(response.statusCode) {
            completionHandler(.cancel)
            finish(with: nil)
        } else {
            completionHandler(.allow)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !isFinished else { return }
        receivedData.append(data)
        CGImageSourceUpdateData(imageSource, receivedData as CFData, false)
        if let size = Self.imageDimensions(from: imageSource) {
            finish(with: size)
        } else if receivedData.count >= Self.byteLimit {
            finish(with: nil)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        guard !isFinished else { return }
        CGImageSourceUpdateData(imageSource, receivedData as CFData, true)
        finish(with: Self.imageDimensions(from: imageSource))
    }

    private var isFinished: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return finished
    }

    private func finish(with size: CGSize?) {
        stateLock.lock()
        guard !finished else {
            stateLock.unlock()
            return
        }
        finished = true
        let task = task
        let session = session
        let continuation = continuation
        self.task = nil
        self.session = nil
        self.continuation = nil
        stateLock.unlock()

        task?.cancel()
        session?.invalidateAndCancel()
        continuation?.resume(returning: size)
    }

    private static func imageDimensions(from data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return imageDimensions(from: source)
    }

    private static func imageDimensions(from source: CGImageSource) -> CGSize? {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any]
        else { return nil }
        return imageDimensions(from: properties)
    }

    private static func imageDimensions(from properties: [CFString: Any]) -> CGSize? {
        guard
            let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
            let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
            width.doubleValue > 0,
            height.doubleValue > 0
        else { return nil }
        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }
}
