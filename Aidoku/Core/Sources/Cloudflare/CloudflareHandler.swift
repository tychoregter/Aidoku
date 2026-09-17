//
//  CloudflareHandler.swift
//  Aidoku
//
//  Created by Skitty on 6/15/25.
//

import AidokuRunner
import Foundation
import SwiftSoup
import WebKit

// handles requests blocked by cloudflare, retrieving new cookies from a webview
// and showing a popup to complete a captcha if necessary
actor CloudflareHandler: NSObject {
    static let shared = CloudflareHandler()

    private let blockedStatusCodes: Set<Int> = [403, 503]

    private struct ChallengeKey: Hashable {
        let host: String

        init?(url: URL?) {
            guard let host = url?.host?.lowercased() else { return nil }
            self.host = host
        }
    }
    private struct ChallengeTask {
        let id: UUID
        let task: Task<Void, Error>
    }
    private var challenges: [ChallengeKey: ChallengeTask] = [:]

    private var shouldTimeout = true
    private var finishContinuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var proxy: Proxy?
    private var isChallengeActive = false
    private var challengeWaiters: [CheckedContinuation<Void, Never>] = []
    private var flareSolverrUserAgents: [String: String] = [:]

    private static let flareSolverrUserAgentDefaultsPrefix = "CloudflareHandler.FlareSolverrUserAgent."

    @MainActor
    private lazy var webView = WKWebView(frame: .zero)

    @MainActor
    private var popupController: WebViewViewController?

    @MainActor
    private var popupShown: Bool {
        popupController?.presentingViewController != nil
    }

    @MainActor
    private var parent: UIViewController? {
        guard let root = UIApplication.shared.firstKeyWindow?.rootViewController else {
            return nil
        }

        // Browse can be hosted by the Settings container rather than a
        // UINavigationController. Resolve the selected tab generically so
        // Cloudflare can attach its hidden web view in either layout.
        var controller = (root as? UITabBarController)?.selectedViewController ?? root
        while let presented = controller.presentedViewController {
            controller = presented
        }
        return controller
    }

    @MainActor
    private var parentView: UIView? {
        parent?.view
    }

    enum HandleError: Error {
        case invalidRequest
        case missingParentView
        case timedOut
        case canceled
        case solveFailed
    }

    nonisolated func shouldHandle(response: HTTPURLResponse, data: Data) -> Bool {
        let server = response.value(forHTTPHeaderField: "Server")
        if !["cloudflare", "cloudflare-nginx"].contains(server) {
            return false
        }
        if !blockedStatusCodes.contains(response.statusCode) {
            return false
        }

        guard let html = String(data: data, encoding: .utf8) else { return false }
        do {
            let doc = try SwiftSoup.parse(html)
            if try doc.getElementById("challenge-error-title") != nil {
                return true
            }
            if try doc.getElementById("challenge-error-text") != nil {
                return true
            }
        } catch {}
        return false
    }

    func handle(request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await solveWithFlareSolverr(request: request)
        } catch {
            guard AppSettings.general.flareSolverrFallback.get() else {
                throw error
            }
        }

        // handle challenges one at a time, waiting for a solution for the request url host
        try await awaitChallenge(for: request)

        // retry request
        let newRequest = if let url = request.url {
            await AidokuRunner.Source.modify(url: url, request: request)
        } else {
            request
        }
        let (data, response) = try await URLSession.shared.data(for: newRequest)
        if
            let response = response as? HTTPURLResponse,
            shouldHandle(response: response, data: data)
        {
            throw HandleError.solveFailed
        }
        return (data, response)
    }

    /// Returns the browser user-agent paired with a FlareSolverr clearance
    /// cookie for this host. Cloudflare binds `cf_clearance` to the user-agent,
    /// so normal source requests must use the same one after a solve.
    func userAgent(for url: URL) -> String? {
        if let host = url.host?.lowercased(), let userAgent = flareSolverrUserAgents[host] {
            return userAgent
        }
        return Self.cachedFlareSolverrUserAgent(for: url)
    }

    /// Synchronous counterpart for the legacy WASM networking layer.
    nonisolated static func cachedFlareSolverrUserAgent(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        let labels = host.split(separator: ".")
        guard labels.count >= 2 else { return nil }

        // Prefer the most specific matching domain, then fall back to the
        // registrable-domain-like suffix used by a shared Cloudflare cookie.
        for index in 0..<(labels.count - 1) {
            let domain = labels[index...].joined(separator: ".")
            if let userAgent = UserDefaults.standard.string(
                forKey: flareSolverrUserAgentDefaultsPrefix + domain
            ) {
                return userAgent
            }
        }
        return nil
    }

    private func solveWithFlareSolverr(request: URLRequest) async throws -> (Data, URLResponse) {
        let configuredURL = AppSettings.general.flareSolverrURL.get().trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !configuredURL.isEmpty,
            let apiURL = Self.flareSolverrAPIURL(from: configuredURL),
            let targetURL = request.url
        else {
            throw HandleError.solveFailed
        }

        let isPost = request.httpMethod?.uppercased() == "POST"
        var body: [String: Any] = [
            "cmd": isPost ? "request.post" : "request.get",
            "url": targetURL.absoluteString,
            "maxTimeout": 120_000
        ]
        if let host = targetURL.host?.lowercased(), let userAgent = flareSolverrUserAgents[host] {
            body["userAgent"] = userAgent
        }
        if isPost, let httpBody = request.httpBody {
            guard let postData = String(data: httpBody, encoding: .utf8) else {
                throw HandleError.solveFailed
            }
            body["postData"] = postData
        }

        var solverRequest = URLRequest(url: apiURL)
        solverRequest.httpMethod = "POST"
        solverRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        solverRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: solverRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HandleError.solveFailed
        }

        let result = try JSONDecoder().decode(FlareSolverrResponse.self, from: data)
        guard result.status == "ok", let solution = result.solution, solution.status < 400 else {
            throw HandleError.solveFailed
        }

        if let userAgent = solution.userAgent {
            storeFlareSolverrUserAgent(userAgent, for: targetURL, cookies: solution.cookies)
        }
        storeFlareSolverrCookies(solution.cookies, for: targetURL)

        guard let responseData = solution.response.data(using: .utf8) else {
            throw HandleError.solveFailed
        }
        var headers = solution.headers ?? [:]
        headers.removeValue(forKey: "content-encoding")
        headers.removeValue(forKey: "content-length")
        let solvedResponse = HTTPURLResponse(
            url: URL(string: solution.url) ?? targetURL,
            statusCode: solution.status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) ?? httpResponse
        return (responseData, solvedResponse)
    }

    private func storeFlareSolverrCookies(_ cookies: [FlareSolverrCookie], for url: URL) {
        if cookies.contains(where: { $0.name == "cf_clearance" }) {
            HTTPCookieStorage.shared.removeClearanceCookies(for: url)
        }
        for cookie in cookies {
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: cookie.name,
                .value: cookie.value,
                .domain: cookie.domain ?? url.host ?? "",
                .path: cookie.path ?? "/"
            ]
            if let expires = cookie.expires {
                properties[.expires] = Date(timeIntervalSince1970: expires)
            }
            if let httpCookie = HTTPCookie(properties: properties) {
                HTTPCookieStorage.shared.setCookie(httpCookie)
            }
        }
    }

    private func storeFlareSolverrUserAgent(
        _ userAgent: String,
        for url: URL,
        cookies: [FlareSolverrCookie]
    ) {
        var domains = Set<String>()
        if let host = url.host?.lowercased() {
            domains.insert(host)
        }
        for cookie in cookies where cookie.name == "cf_clearance" {
            if let domain = cookie.domain?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) {
                domains.insert(domain)
            }
        }

        for domain in domains {
            flareSolverrUserAgents[domain] = userAgent
            UserDefaults.standard.set(
                userAgent,
                forKey: Self.flareSolverrUserAgentDefaultsPrefix + domain
            )
        }
    }

    private static func flareSolverrAPIURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let normalized = trimmed.hasSuffix("/v1") ? trimmed : trimmed + "/v1"
        guard let url = URL(string: normalized), url.scheme != nil, url.host != nil else { return nil }
        return url
    }
}

private struct FlareSolverrResponse: Decodable {
    let status: String
    let solution: FlareSolverrSolution?
}

private struct FlareSolverrSolution: Decodable {
    let url: String
    let status: Int
    let headers: [String: String]?
    let response: String
    let cookies: [FlareSolverrCookie]
    let userAgent: String?
}

private struct FlareSolverrCookie: Decodable {
    let name: String
    let value: String
    let domain: String?
    let path: String?
    let expires: TimeInterval?
}

extension CloudflareHandler {
    private func completeChallenge(for request: URLRequest) async throws {
        shouldTimeout = true

        guard await addWebView(for: request) else { throw HandleError.missingParentView }

        _ = await webView.load(request)

        try await withCheckedThrowingContinuation { continuation in
            self.finishContinuation = continuation

            // timeout after 12s if bypass doesn't work
            timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                guard !Task.isCancelled else { return }

                if self.shouldTimeout, finishContinuation != nil {
                    self.finishChallenge(with: .failure(HandleError.timedOut))
                }
            }
        }
    }

    private func finishChallenge(with result: Result<Void, Error> = .success(())) {
        guard let continuation = finishContinuation else { return }

        Task { @MainActor in
            webView.removeFromSuperview()
            popupController?.dismiss(animated: true)
            popupController = nil
        }

        timeoutTask?.cancel()
        finishContinuation = nil
        timeoutTask = nil
        proxy = nil

        continuation.resume(with: result)
    }

    private func proxy(for request: URLRequest) async -> Proxy {
        if let proxy {
            return proxy
        }
        let proxy = await Proxy(request: request, handler: self)
        self.proxy = proxy
        return proxy
    }

    // add hidden web view to a visible view controller
    @MainActor
    private func addWebView(for request: URLRequest) async -> Bool {
        guard let parentView else { return false }

        // match web view rendering mode with user agent
        let userAgent = request.value(forHTTPHeaderField: "User-Agent")
        let config = WKWebViewConfiguration()
        if let userAgent, userAgent.contains("iPhone") || userAgent.contains("iPad") {
            config.defaultWebpagePreferences.preferredContentMode = .mobile
        }
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = await proxy(for: request)
        webView.customUserAgent = userAgent
        webView.translatesAutoresizingMaskIntoConstraints = false
        parentView.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.widthAnchor.constraint(equalToConstant: 0),
            webView.heightAnchor.constraint(equalToConstant: 0),
            webView.centerXAnchor.constraint(equalTo: parentView.centerXAnchor),
            webView.centerYAnchor.constraint(equalTo: parentView.centerYAnchor)
        ])

        return true
    }

    private func awaitChallenge(for request: URLRequest) async throws {
        guard let key = ChallengeKey(url: request.url) else {
            throw HandleError.invalidRequest
        }

        if let challenge = challenges[key] {
            return try await challenge.task.value
        }

        let id = UUID()

        let task = Task { [weak self] in
            guard let self else { throw CancellationError() }

            await self.acquire()

            do {
                try Task.checkCancellation()
                try await self.completeChallenge(for: request)
                await self.release()
            } catch {
                await self.release()
                throw error
            }
        }

        challenges[key] = .init(id: id, task: task)

        do {
            try await task.value
        } catch {
            if challenges[key]?.id == id {
                challenges[key] = nil
            }
            throw error
        }

        if challenges[key]?.id == id {
            challenges[key] = nil
        }
    }

    private func acquire() async {
        guard !isChallengeActive else {
            await withCheckedContinuation { continuation in
                challengeWaiters.append(continuation)
            }
            return
        }
        isChallengeActive = true
    }

    private func release() {
        if !challengeWaiters.isEmpty {
            challengeWaiters.removeFirst().resume()
        } else {
            isChallengeActive = false
        }
    }
}

extension CloudflareHandler {
    @MainActor
    final class Proxy: NSObject, PopupWebViewHandler, WKNavigationDelegate {
        let request: URLRequest

        weak var handler: CloudflareHandler?

        init(request: URLRequest, handler: CloudflareHandler) {
            self.request = request
            self.handler = handler
        }

        func navigated(webView: WKWebView, for request: URLRequest) {
            Task { [weak handler] in
                await handler?.navigated(webView: webView, for: request)
            }
        }

        func canceled(request: URLRequest) {
            Task { [weak handler] in
                await handler?.canceled(request: request)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            navigated(webView: webView, for: request)
        }
    }

    // handle web view reload/redirect
    nonisolated func navigated(webView: WKWebView, for request: URLRequest) async {
        guard let url = request.url, let host = url.host?.lowercased() else { return }

        await MainActor.run {
            if self.popupController == nil {
                // delay captcha check by 3s (so it loads in)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    self?.checkForCaptcha(for: request)
                }
                // try again in 5s if the first check didn't catch the captcha (dumb hack)
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                    self?.checkForCaptcha(for: request)
                }
            }
        }

        var webViewCookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()

        // Check for old clearance cookies. A second value with the same name
        // can make the server reject the request depending on which value it
        // parses first, so replace every matching clearance cookie at once.
        let oldCookies = HTTPCookieStorage.shared.allCookies(for: url)?.filter { $0.name == "cf_clearance" } ?? []

        // check for clearance cookie
        let hasClearance = webViewCookies.contains { cookie in
            let domain = cookie.domain
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return cookie.name == "cf_clearance"
                && !oldCookies.contains(where: { $0.value == cookie.value })
                && (host == domain || host.hasSuffix("." + domain))
        }
        guard hasClearance else { return }

        // Remove old values and save the new web-view session for future
        // source requests.
        HTTPCookieStorage.shared.removeClearanceCookies(for: url)
        for oldCookie in oldCookies {
            if let idx = webViewCookies.firstIndex(of: oldCookie) {
                webViewCookies.remove(at: idx)
            }
        }
        HTTPCookieStorage.shared.setCookies(webViewCookies, for: url, mainDocumentURL: url)

        let isCaptcha = await isCaptchaPage()
        guard !isCaptcha else { return }

        await webView.removeFromSuperview()
        await self.popupController?.dismiss(animated: true)

        await self.finishChallenge()
    }

    // handle user popover dismiss
    nonisolated func canceled(request: URLRequest) async {
        await self.finishChallenge(with: .failure(HandleError.canceled))
    }
}

extension CloudflareHandler {
    private func disableTimeout() {
        shouldTimeout = false
    }

    // show captcha sheet view to user
    @MainActor
    private func showPopup(for request: URLRequest) async {
        guard !popupShown else { return }

        // don't timeout while popup is shown
        await disableTimeout()

        guard let parent else {
            await self.finishChallenge(with: .failure(HandleError.missingParentView))
            return
        }

        popupController?.dismiss(animated: true)
        let popup = WebViewViewController(request: request, handler: await proxy(for: request))
        popupController = popup

        webView.navigationDelegate = popup
        webView.removeFromSuperview()
        popup.view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.widthAnchor.constraint(equalTo: popup.view.widthAnchor),
            webView.heightAnchor.constraint(equalTo: popup.view.heightAnchor),
            webView.centerXAnchor.constraint(equalTo: popup.view.centerXAnchor),
            webView.centerYAnchor.constraint(equalTo: popup.view.centerYAnchor)
        ])

        parent.present(popup, animated: true)
    }

    // check if captcha or verify button is shown, and show the popup if it is
    @MainActor
    private func checkForCaptcha(for request: URLRequest) {
        guard !popupShown else { return }
        Task {
            let found = await isCaptchaPage()
            if found {
                await showPopup(for: request)
            }
        }
    }

    @MainActor
    private func isCaptchaPage() async -> Bool {
        let js = """
        (document.querySelector('input[name="cf-turnstile-response"]') !== null
            || document.getElementById('challenge-error-title') !== null
            || document.getElementById('challenge-error-text') !== null) ? 1 : 0
            || document.title === "Just a moment..."
        """
        let result = try? await webView.evaluateJavaScript(js)
        guard let result = result as? Int else { return false }
        return result == 1
    }
}

extension HTTPCookieStorage {
    func allCookies(for url: URL) -> [HTTPCookie]? {
        guard let host = url.host else { return nil }
        return cookies?.filter { cookie in
            let domain = cookie.domain
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let cookiePath = cookie.path.isEmpty ? "/" : cookie.path
            let requestPath = url.path.isEmpty ? "/" : url.path
            return (host == domain || host.hasSuffix("." + domain))
                && requestPath.hasPrefix(cookiePath)
        }
    }

    /// Builds one deterministic Cookie header. Stored cookies win over stale
    /// values supplied by a source, preventing duplicate `cf_clearance`
    /// values after a Cloudflare solve.
    func cookieHeader(for url: URL, appending existingHeader: String?) -> String? {
        var values: [String: String] = [:]
        var order: [String] = []

        func add(_ header: String?, replacingExisting: Bool) {
            guard let header else { return }
            for part in header.split(separator: ";") {
                let pieces = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard pieces.count == 2 else { continue }
                let name = pieces[0].trimmingCharacters(in: .whitespaces)
                let value = pieces[1].trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                if values[name] == nil {
                    order.append(name)
                }
                if replacingExisting || values[name] == nil {
                    values[name] = value
                }
            }
        }

        // Preserve source-specific cookies, then overwrite duplicates with
        // the verified cookies from the shared session.
        add(existingHeader, replacingExisting: false)
        let storedHeader = HTTPCookie.requestHeaderFields(with: allCookies(for: url) ?? [])["Cookie"]
        add(storedHeader, replacingExisting: true)

        guard !order.isEmpty else { return nil }
        return order.compactMap { name in
            values[name].map { "\(name)=\($0)" }
        }.joined(separator: "; ")
    }

    func removeClearanceCookies(for url: URL) {
        for cookie in allCookies(for: url) ?? [] where cookie.name == "cf_clearance" {
            deleteCookie(cookie)
        }
    }
}
