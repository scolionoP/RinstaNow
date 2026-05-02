import SwiftUI
import WebKit

struct AuthCaptureResult {
    var cookieHeader: String
    var snapshot: WebBootstrapSnapshot
}

struct AuthWebView: NSViewRepresentable {
    @Binding var captureTrigger: Int
    var onCapture: (AuthCaptureResult) -> Void
    var onStatus: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onStatus: onStatus)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(captureScript)

        let preferences = WKPreferences()
        preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.preferences = preferences

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = UserAgent.desktopChrome
        context.coordinator.webView = webView
        webView.load(URLRequest(url: URL(string: "https://www.instagram.com/direct/inbox/")!))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastCaptureTrigger != captureTrigger else { return }
        context.coordinator.lastCaptureTrigger = captureTrigger
        context.coordinator.capture()
    }

    private var captureScript: WKUserScript {
        WKUserScript(
            source: """
            window.__igClientCapture = function() {
              const readModule = (name) => {
                try {
                  if (typeof require === 'function') return require(name);
                } catch (e) {}
                try {
                  if (window.require && typeof window.require === 'function') return window.require(name);
                } catch (e) {}
                return null;
              };

              const first = (...values) => {
                for (const value of values) {
                  if (value !== undefined && value !== null && String(value).length > 0) return String(value);
                }
                return null;
              };

              const siteData = readModule('SiteData') || {};
              const dtsg = readModule('DTSGInitialData') || readModule('DTSG') || {};
              const lsd = readModule('LSD') || {};
              const currentUser = readModule('CurrentUserInitialData') || {};
              const config = window._sharedData?.config || {};
              const rollout = window.__additionalDataLoaded ? null : null;

              return {
                fbDtsg: first(dtsg.token, dtsg.__bbox?.result?.data?.viewer?.actor?.__isActor),
                lsd: first(lsd.token, document.querySelector('input[name="lsd"]')?.value),
                appID: first(siteData.app_id, config.viewer?.app_id, '936619743392459'),
                userID: first(currentUser.IG_USER_ID, currentUser.USER_ID, config.viewer?.id),
                accountID: first(currentUser.ACCOUNT_ID, currentUser.IG_USER_EIMU, currentUser.IG_USER_ID),
                revision: first(siteData.__spin_r, siteData.client_revision, siteData.revision),
                spinR: first(siteData.__spin_r, siteData.client_revision, siteData.revision),
                spinB: first(siteData.__spin_b, 'trunk'),
                spinT: first(siteData.__spin_t),
                hasteSession: first(siteData.pkg_cohort, siteData.haste_session),
                hsi: first(siteData.hsi),
                connectionClass: first(siteData.connection_class, 'EXCELLENT'),
                dyn: first(siteData.dyn),
                csr: first(siteData.csr),
                hsdp: first(siteData.hsdp),
                hblp: first(siteData.hblp),
                sjsp: first(siteData.sjsp),
                reqCounter: '1',
                dpr: first(window.devicePixelRatio),
                userAgent: navigator.userAgent,
                platformVersion: first(navigator.userAgentData?.platformVersion),
                url: location.href
              };
            };
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onCapture: (AuthCaptureResult) -> Void
        var onStatus: (String) -> Void
        weak var webView: WKWebView?
        var lastCaptureTrigger = 0

        init(onCapture: @escaping (AuthCaptureResult) -> Void, onStatus: @escaping (String) -> Void) {
            self.onCapture = onCapture
            self.onStatus = onStatus
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onStatus(webView.url?.absoluteString ?? "Loaded")
        }

        func capture() {
            guard let webView else { return }

            webView.evaluateJavaScript("window.__igClientCapture && window.__igClientCapture()") { [weak self] value, error in
                if let error {
                    self?.onStatus(error.localizedDescription)
                    return
                }

                let snapshot = WebBootstrapSnapshot(dictionary: value as? [String: Any] ?? [:])
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                    let instagramCookies = cookies
                        .filter { $0.domain.contains("instagram.com") }
                        .sorted { $0.name < $1.name }
                        .map { "\($0.name)=\($0.value)" }
                        .joined(separator: "; ")

                    DispatchQueue.main.async {
                        self?.onCapture(AuthCaptureResult(cookieHeader: instagramCookies, snapshot: snapshot))
                    }
                }
            }
        }
    }
}

extension WebBootstrapSnapshot {
    init(dictionary: [String: Any]) {
        self.init(
            fbDtsg: dictionary.string("fbDtsg"),
            lsd: dictionary.string("lsd"),
            appID: dictionary.string("appID"),
            userID: dictionary.string("userID"),
            accountID: dictionary.string("accountID"),
            revision: dictionary.string("revision"),
            spinR: dictionary.string("spinR"),
            spinB: dictionary.string("spinB"),
            spinT: dictionary.string("spinT"),
            hasteSession: dictionary.string("hasteSession"),
            hsi: dictionary.string("hsi"),
            connectionClass: dictionary.string("connectionClass"),
            dyn: dictionary.string("dyn"),
            csr: dictionary.string("csr"),
            hsdp: dictionary.string("hsdp"),
            hblp: dictionary.string("hblp"),
            sjsp: dictionary.string("sjsp"),
            reqCounter: dictionary.string("reqCounter"),
            dpr: dictionary.string("dpr"),
            userAgent: dictionary.string("userAgent"),
            platformVersion: dictionary.string("platformVersion"),
            url: dictionary.string("url")
        )
    }
}

private extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? {
        guard let value = self[key], !(value is NSNull) else { return nil }
        return nonEmpty(String(describing: value))
    }
}
