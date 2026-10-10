//
//  CloudflareHandler.swift
//  Aidoku
//
//  Created by Skitty on 6/15/25.
//

import AidokuRunner
import Foundation
import WebKit

// handles requests blocked by cloudflare, retrieving new cookies from a webview
// and showing a popup to complete a captcha if necessary
actor CloudflareHandler: NSObject {
    static let shared = CloudflareHandler()

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
    private var pendingPopupTask: Task<Void, Never>?

    @MainActor
    private var pendingPopupID: UUID?

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
        if response.value(forHTTPHeaderField: "cf-mitigated")?.lowercased() == "challenge" {
            return true
        }
        guard response.value(forHTTPHeaderField: "Server")?.lowercased().hasPrefix("cloudflare") == true else {
            return false
        }
        guard let html = String(data: data, encoding: .utf8) else { return false }
        // Older challenge responses may omit cf-mitigated or use HTTP 200.
        return html.contains("cdn-cgi/challenge-platform")
            || html.contains("_cf_chl_opt")
            || html.contains("challenge-error-title")
            || html.contains("challenge-error-text")
            || html.range(of: "<title>Just a moment", options: .caseInsensitive) != nil
    }

    func handle(request: URLRequest) async throws -> (Data, URLResponse) {
        let configuredURL = AppSettings.general.flareSolverrURL.get().trimmingCharacters(in: .whitespacesAndNewlines)
        if !configuredURL.isEmpty {
            do {
                if let solvedResponse = try await solveWithFlareSolverr(request: request) {
                    return solvedResponse
                }
                return try await retry(request: request, route: "FlareSolverr")
            } catch {
                guard AppSettings.general.flareSolverrFallback.get() else {
                    throw error
                }
            }
        }

        // handle challenges one at a time, waiting for a solution for the request url host
        let manualRequest = await prepareManualRequest(request)
        try await awaitChallenge(for: manualRequest)
        return try await retry(request: manualRequest, route: "manual verification")
    }

    private func retry(request: URLRequest, route: String) async throws -> (Data, URLResponse) {
        let newRequest = if let url = request.url {
            await AidokuRunner.Source.modify(url: url, request: request)
        } else {
            request
        }
        let (data, response) = try await URLSession.shared.data(for: newRequest)
        if let response = response as? HTTPURLResponse {
            let host = newRequest.url?.host ?? "unknown host"
            if shouldHandle(response: response, data: data) {
                LogManager.logger.error("Cloudflare challenge returned after \(route) for \(host) (HTTP \(response.statusCode))")
                throw HandleError.solveFailed
            }
            if response.statusCode >= 400 {
                LogManager.logger.error("Cloudflare retry after \(route) returned HTTP \(response.statusCode) for \(host)")
            }
        }
        return (data, response)
    }

    private func prepareManualRequest(_ request: URLRequest) async -> URLRequest {
        guard let url = request.url else { return request }
        var manualRequest = request

        // A former FlareSolverr session can outlive its configured server URL.
        // Its desktop user-agent and clearance cookie must not be carried into
        // an iOS web-view verification session.
        if let oldUserAgent = Self.storedFlareSolverrUserAgent(for: url) {
            let labels = (url.host ?? "").lowercased().split(separator: ".")
            if labels.count >= 2 {
                for index in 0..<(labels.count - 1) {
                    let domain = labels[index...].joined(separator: ".")
                    flareSolverrUserAgents.removeValue(forKey: domain)
                    UserDefaults.standard.removeObject(forKey: Self.flareSolverrUserAgentDefaultsPrefix + domain)
                }
            }
            HTTPCookieStorage.shared.removeClearanceCookies(for: url)
            if let cookieHeader = manualRequest.value(forHTTPHeaderField: "Cookie") {
                let remainingCookies = cookieHeader.split(separator: ";").filter { part in
                    let name = String(part.split(separator: "=", maxSplits: 1).first ?? "")
                        .trimmingCharacters(in: .whitespaces)
                    return name.caseInsensitiveCompare("cf_clearance") != .orderedSame
                }.joined(separator: "; ")
                manualRequest.setValue(remainingCookies.isEmpty ? nil : remainingCookies, forHTTPHeaderField: "Cookie")
            }
            if manualRequest.value(forHTTPHeaderField: "User-Agent") == oldUserAgent {
                manualRequest.setValue(await UserAgentProvider.shared.getUserAgent(), forHTTPHeaderField: "User-Agent")
            }
        }

        return await AidokuRunner.Source.modify(url: url, request: manualRequest)
    }

    /// Returns the browser user-agent paired with a FlareSolverr clearance
    /// cookie for this host. Cloudflare binds `cf_clearance` to the user-agent,
    /// so normal source requests must use the same one after a solve.
    func userAgent(for url: URL) -> String? {
        guard !AppSettings.general.flareSolverrURL.get().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        if let host = url.host?.lowercased(), let userAgent = flareSolverrUserAgents[host] {
            return userAgent
        }
        return Self.cachedFlareSolverrUserAgent(for: url)
    }

    /// Synchronous counterpart for the legacy WASM networking layer.
    nonisolated static func cachedFlareSolverrUserAgent(for url: URL) -> String? {
        guard !AppSettings.general.flareSolverrURL.get().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return storedFlareSolverrUserAgent(for: url)
    }

    private nonisolated static func storedFlareSolverrUserAgent(for url: URL) -> String? {
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

    private func solveWithFlareSolverr(request: URLRequest) async throws -> (Data, URLResponse)? {
        let configuredURL = AppSettings.general.flareSolverrURL.get().trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !configuredURL.isEmpty,
            let apiURL = Self.flareSolverrAPIURL(from: configuredURL),
            let targetURL = request.url
        else {
            throw HandleError.solveFailed
        }
        let method = (request.httpMethod ?? "GET").uppercased()
        let host = targetURL.host ?? "unknown host"
        LogManager.logger.log("FlareSolverr handling \(method) \(host)\(targetURL.path)")

        let body: [String: Any] = [
            // FlareSolverr fetches the challenged URL in its browser. Its
            // response can be used directly for GET requests, avoiding a
            // second request from a different client fingerprint.
            "cmd": "request.get",
            "url": targetURL.absoluteString,
            "maxTimeout": 120_000
        ]
        var solverRequest = URLRequest(url: apiURL)
        solverRequest.httpMethod = "POST"
        solverRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        solverRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: solverRequest)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw HandleError.solveFailed
        }

        let result = try JSONDecoder().decode(FlareSolverrResponse.self, from: data)
        guard result.status == "ok", let solution = result.solution, solution.status < 400 else {
            throw HandleError.solveFailed
        }
        LogManager.logger.log(
            "FlareSolverr result for \(host): HTTP \(solution.status), body \(solution.response?.utf8.count ?? 0) bytes"
        )

        let solvedResponse: (Data, URLResponse)?
        if method == "GET" {
            guard (200..<300).contains(solution.status), let responseBody = solution.response else {
                LogManager.logger.error("FlareSolverr did not return a usable response for \(targetURL.host ?? "unknown host")")
                throw HandleError.solveFailed
            }
            // FlareSolverr returns the decoded body as a string. Do not pass
            // through a challenge or Chromium error page even if the solver
            // reported success (its status may still be 200 for a browser 404).
            if responseBody.contains("id=\"main-frame-error\"")
                || responseBody.contains("No webpage was found for the web address") {
                let errorCode = responseBody.range(of: #"HTTP ERROR \d{3}"#, options: .regularExpression)
                    .map { String(responseBody[$0]) } ?? "browser error"
                LogManager.logger.error("FlareSolverr returned \(errorCode) for \(targetURL.host ?? "unknown host")")
                throw HandleError.solveFailed
            }
            let browserJSON = Self.browserWrappedJSON(from: responseBody)
            let responseData = browserJSON ?? Data(responseBody.utf8)
            var headers = solution.headers ?? [:]
            headers = headers.filter { key, _ in
                !["content-encoding", "content-length", "transfer-encoding"].contains(key.lowercased())
            }
            if browserJSON != nil {
                headers = headers.filter { $0.key.lowercased() != "content-type" }
                headers["Content-Type"] = "application/json; charset=utf-8"
            }
            guard let httpResponse = HTTPURLResponse(
                url: targetURL,
                statusCode: solution.status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            ) else {
                throw HandleError.solveFailed
            }
            if shouldHandle(response: httpResponse, data: responseData)
                || responseBody.range(of: "<title>Just a moment", options: .caseInsensitive) != nil
                || responseBody.contains("cdn-cgi/challenge-platform") {
                throw HandleError.solveFailed
            }
            solvedResponse = (responseData, httpResponse)
            LogManager.logger.log("FlareSolverr using its response directly for \(host)")
        } else {
            LogManager.logger.log("FlareSolverr retrying \(method) from Aidoku for \(host); direct response requires GET")
            solvedResponse = nil
        }

        if let userAgent = solution.userAgent {
            storeFlareSolverrUserAgent(userAgent, for: targetURL, cookies: solution.cookies)
        }
        storeFlareSolverrCookies(solution.cookies, for: targetURL)
        return solvedResponse
    }

    /// Chromium wraps JSON responses in an HTML document containing a `pre`.
    /// FlareSolverr returns that page source, not the original response bytes.
    private static func browserWrappedJSON(from pageSource: String) -> Data? {
        let pattern = #"(?is)<body[^>]*>\s*<pre[^>]*>(.*?)</pre>\s*</body>"#
        guard let match = pageSource.range(of: pattern, options: .regularExpression),
              let preStart = pageSource[match].range(of: "<pre", options: .caseInsensitive),
              let contentStart = pageSource[preStart.upperBound...].firstIndex(of: ">"),
              let contentEnd = pageSource[contentStart...].range(of: "</pre>", options: .caseInsensitive)?.lowerBound
        else {
            return nil
        }

        let escaped = String(pageSource[pageSource.index(after: contentStart)..<contentEnd])
        let json = escaped
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
        let data = Data(json.utf8)
        guard (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) != nil else {
            return nil
        }
        return data
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
    let status: Int
    let headers: [String: String]?
    let response: String?
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
            pendingPopupTask?.cancel()
            pendingPopupTask = nil
            pendingPopupID = nil
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

    private func hasPendingChallenge() -> Bool {
        finishContinuation != nil
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
        guard await hasPendingChallenge() else { return }

        // don't timeout while popup is shown
        await disableTimeout()

        guard let parent else {
            await self.finishChallenge(with: .failure(HandleError.missingParentView))
            return
        }

        popupController?.dismiss(animated: true)
        let popup = WebViewViewController(request: request, handler: await proxy(for: request))
        guard await hasPendingChallenge() else { return }
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
        guard !popupShown, pendingPopupTask == nil else { return }
        let id = UUID()
        pendingPopupID = id
        pendingPopupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.pendingPopupID == id {
                    self.pendingPopupTask = nil
                    self.pendingPopupID = nil
                }
            }
            guard await self.isCaptchaPage() else { return }

            // Brief automatic checks can finish just after the challenge UI
            // appears. Keep the web view hidden until it is clearly waiting
            // for user interaction.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, !self.popupShown else { return }
            guard await self.isCaptchaPage() else { return }
            await self.showPopup(for: request)
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
