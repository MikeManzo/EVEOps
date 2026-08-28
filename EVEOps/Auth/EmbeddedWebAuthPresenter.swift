//
// This file is part of EVEOps.
//
// EVEOps is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import AppKit
import WebKit

/// Presenter for OAuth clients whose redirect_uri is a plain HTTPS page CCP owns (e.g. CCP's own
/// launcher client, `eveLauncherTQ`, redirects to `https://login.eveonline.com/launcher`) rather
/// than a URL scheme EVEOps registers. `ASWebAuthenticationSession` can only intercept a
/// callback via a scheme the app owns or a universal link the destination server has listed the
/// app for — neither applies here, since EVEOps doesn't control CCP's redirect target.
///
/// Instead, this hosts the login page in an app-owned `WKWebView` and watches outgoing
/// navigations itself: the moment one targets the expected redirect page, the navigation is
/// cancelled before it loads (so the query-string-bearing URL is captured but the page — which
/// would 404 or show a bare CCP page never meant to be viewed directly — never actually renders).
@MainActor
final class EmbeddedWebAuthPresenter: NSObject, AuthorizationCallbackPresenting {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<URL, Error>?
    private var matchPrefix: String = ""

    func presentAndAwaitCallback(
        authURL: URL,
        callbackURLString: String,
        forceFreshSession: Bool
    ) async throws -> URL {
        // Match on scheme+host+path only — the real redirect carries `code`/`state` query items
        // the original redirect_uri (still holding its own `client_id` query item) never had.
        var prefixComponents = URLComponents(string: callbackURLString)
        prefixComponents?.query = nil
        prefixComponents?.fragment = nil
        matchPrefix = prefixComponents?.string ?? callbackURLString

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            self.continuation = continuation

            let configuration = WKWebViewConfiguration()
            if forceFreshSession {
                configuration.websiteDataStore = .nonPersistent()
            }
            let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 640), configuration: configuration)
            webView.navigationDelegate = self
            self.webView = webView

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Log In to EVE Online"
            window.contentView = webView
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window

            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            webView.load(URLRequest(url: authURL))
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        window?.delegate = nil
        window?.close()
        window = nil
        webView = nil
        switch result {
        case .success(let url): continuation.resume(returning: url)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }
}

extension EmbeddedWebAuthPresenter: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let url = navigationAction.request.url, url.absoluteString.hasPrefix(matchPrefix) {
            decisionHandler(.cancel)
            finish(.success(url))
            return
        }
        decisionHandler(.allow)
    }
}

extension EmbeddedWebAuthPresenter: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        finish(.failure(SSOError.invalidCallback))
    }
}
