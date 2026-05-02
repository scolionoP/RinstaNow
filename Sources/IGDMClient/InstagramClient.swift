import Foundation

enum InstagramClientError: LocalizedError {
    case missingSession
    case invalidResponse
    case httpStatus(Int, String)
    case csrfMissing
    case tooManyRedirects
    case missingSendTemplate

    var errorDescription: String? {
        switch self {
        case .missingSession:
            return "No Instagram session cookie is configured."
        case .invalidResponse:
            return "Instagram returned a response the app could not read."
        case let .httpStatus(code, body):
            if code == 401 {
                return "Instagram rejected this browser session. Wait a few minutes, sign back in through your browser, then paste a fresh Cookie header."
            }

            return "Instagram returned HTTP \(code). \(body)"
        case .csrfMissing:
            return "The cookie string does not include csrftoken."
        case .tooManyRedirects:
            return "Instagram redirected this session back to login too many times. Wait a few minutes, sign back in through your browser, then paste a fresh Cookie header."
        case .missingSendTemplate:
            return "Import a HAR file containing a successful IGDirectTextSendMutation before sending messages."
        }
    }
}

struct InstagramSession: Codable, Equatable, Sendable {
    var cookieHeader: String
    var appID: String
    var sendTemplate: GraphQLSendTemplate?

    static let empty = InstagramSession(cookieHeader: "", appID: "936619743392459", sendTemplate: nil)

    var isConfigured: Bool {
        !cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var csrfToken: String? {
        cookieHeader
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.hasPrefix("csrftoken=") }
            .map { String($0.dropFirst("csrftoken=".count)) }
            .flatMap(nonEmpty)
    }

    var dsUserID: String? {
        cookie(named: "ds_user_id")
    }

    func cookie(named name: String) -> String? {
        cookieHeader
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.hasPrefix("\(name)=") }
            .map { String($0.dropFirst(name.count + 1)) }
            .flatMap(nonEmpty)
    }

    func merging(response: HTTPURLResponse) -> InstagramSession {
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: response.allHeaderFields.reduce(into: [String: String]()) { result, item in
            guard let key = item.key as? String,
                  let value = item.value as? String else {
                return
            }

            result[key] = value
        }, for: response.url ?? URL(string: "https://www.instagram.com/")!)

        guard !cookies.isEmpty else {
            return self
        }

        var cookiePairs = cookieHeader
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String: String]()) { result, pair in
                let pieces = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard pieces.count == 2 else { return }
                result[pieces[0]] = pieces[1]
            }

        for cookie in cookies {
            cookiePairs[cookie.name] = cookie.value
        }

        let mergedHeader = cookiePairs
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "; ")

        return InstagramSession(cookieHeader: mergedHeader, appID: appID, sendTemplate: sendTemplate)
    }
}

struct InstagramResult<Value: Sendable>: Sendable {
    var value: Value
    var session: InstagramSession
}

struct GraphQLSendTemplate: Codable, Equatable, Sendable {
    var formFields: [String: String]
    var headers: [String: String]
    var sourceURL: String

    var lsd: String? {
        nonEmpty(formFields["lsd"]) ?? nonEmpty(headers["x-fb-lsd"])
    }

    var friendlyName: String {
        formFields["fb_api_req_friendly_name"] ?? "IGDirectTextSendMutation"
    }
}

struct WebBootstrapSnapshot: Codable, Equatable, Sendable {
    var fbDtsg: String?
    var lsd: String?
    var appID: String?
    var userID: String?
    var accountID: String?
    var revision: String?
    var spinR: String?
    var spinB: String?
    var spinT: String?
    var hasteSession: String?
    var hsi: String?
    var connectionClass: String?
    var dyn: String?
    var csr: String?
    var hsdp: String?
    var hblp: String?
    var sjsp: String?
    var reqCounter: String?
    var dpr: String?
    var userAgent: String?
    var platformVersion: String?
    var url: String?
}

extension GraphQLSendTemplate {
    static func webBootstrap(snapshot: WebBootstrapSnapshot, session: InstagramSession) -> GraphQLSendTemplate {
        let appID = nonEmpty(snapshot.appID) ?? session.appID
        let viewerID = nonEmpty(snapshot.accountID) ?? nonEmpty(snapshot.userID) ?? session.dsUserID ?? "0"
        let revision = nonEmpty(snapshot.revision) ?? nonEmpty(snapshot.spinR) ?? "0"
        let spinTime = nonEmpty(snapshot.spinT) ?? String(Int(Date().timeIntervalSince1970))
        let lsd = nonEmpty(snapshot.lsd) ?? ""
        let fbDtsg = nonEmpty(snapshot.fbDtsg) ?? ""
        let flowID = String(Int.random(in: 10_000_000...99_999_999))

        let variables: [String: Any] = [
            "ig_thread_igid": "",
            "offline_threading_id": "",
            "recipient_igids": NSNull(),
            "replied_to_client_context": NSNull(),
            "replied_to_item_id": NSNull(),
            "reply_to_message_id": NSNull(),
            "sampled": NSNull(),
            "text": ["sensitive_string_value": ""],
            "mentions": [],
            "mentioned_user_ids": [],
            "commands": NSNull(),
            "forwarded_from_thread_id": NSNull(),
            "is_forwarded_from_own_message": NSNull(),
            "send_attribution": "igd_web_chat_tab:in_thread"
        ]

        let variablesData = (try? JSONSerialization.data(withJSONObject: variables, options: [.sortedKeys])) ?? Data("{}".utf8)
        let variablesJSON = String(data: variablesData, encoding: .utf8) ?? "{}"

        let formFields: [String: String] = [
            "av": viewerID,
            "__d": "www",
            "__user": "0",
            "__a": "1",
            "__req": nonEmpty(snapshot.reqCounter) ?? "1",
            "__hs": nonEmpty(snapshot.hasteSession) ?? "",
            "dpr": nonEmpty(snapshot.dpr) ?? "2",
            "__ccg": nonEmpty(snapshot.connectionClass) ?? "EXCELLENT",
            "__rev": revision,
            "__s": "",
            "__hsi": nonEmpty(snapshot.hsi) ?? "",
            "__dyn": nonEmpty(snapshot.dyn) ?? "",
            "__csr": nonEmpty(snapshot.csr) ?? "",
            "__hsdp": nonEmpty(snapshot.hsdp) ?? "",
            "__hblp": nonEmpty(snapshot.hblp) ?? "",
            "__sjsp": nonEmpty(snapshot.sjsp) ?? "",
            "__comet_req": "7",
            "fb_dtsg": fbDtsg,
            "jazoest": jazoest(for: fbDtsg),
            "lsd": lsd,
            "__spin_r": revision,
            "__spin_b": nonEmpty(snapshot.spinB) ?? "trunk",
            "__spin_t": spinTime,
            "__crn": "comet.igweb.PolarisDirectInboxRoute",
            "qpl_active_flow_ids": flowID,
            "fb_api_caller_class": "RelayModern",
            "fb_api_req_friendly_name": "IGDirectTextSendMutation",
            "server_timestamps": "true",
            "variables": variablesJSON,
            "doc_id": "26911679871773184",
            "fb_api_analytics_tags": "[\"qpl_active_flow_ids=\(flowID)\"]"
        ]

        let headers: [String: String] = [
            "user-agent": nonEmpty(snapshot.userAgent) ?? UserAgent.desktopChrome,
            "x-ig-app-id": appID,
            "x-fb-lsd": lsd,
            "x-fb-friendly-name": "IGDirectTextSendMutation",
            "x-asbd-id": "359341",
            "x-ig-max-touch-points": "0",
            "sec-ch-ua": "\"Chromium\";v=\"147\", \"Not.A/Brand\";v=\"8\"",
            "sec-ch-ua-mobile": "?0",
            "sec-ch-ua-model": "\"\"",
            "sec-ch-ua-platform": "\"macOS\"",
            "sec-ch-ua-platform-version": "\"\(nonEmpty(snapshot.platformVersion) ?? "26.0.0")\"",
            "sec-fetch-dest": "empty",
            "sec-fetch-mode": "cors",
            "sec-fetch-site": "same-origin"
        ]

        return GraphQLSendTemplate(
            formFields: formFields,
            headers: headers,
            sourceURL: snapshot.url ?? "https://www.instagram.com/direct/inbox/"
        )
    }

    private static func jazoest(for token: String) -> String {
        let total = token.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return "2\(total)"
    }
}

actor InstagramClient {
    private let decoder: JSONDecoder
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    func fetchInbox(using instagramSession: InstagramSession) async throws -> InstagramResult<InboxResponse> {
        guard instagramSession.isConfigured else {
            throw InstagramClientError.missingSession
        }

        let url = URL(string: "https://www.instagram.com/api/v1/direct_v2/inbox/?persistentBadging=true&folder=&limit=20")!
        let response = try await data(for: request(url: url, instagramSession: instagramSession), instagramSession: instagramSession)
        return InstagramResult(value: try decoder.decode(InboxResponse.self, from: response.data), session: response.session)
    }

    func fetchThread(id: String, using instagramSession: InstagramSession) async throws -> InstagramResult<ThreadResponse> {
        guard instagramSession.isConfigured else {
            throw InstagramClientError.missingSession
        }

        let escapedID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let url = URL(string: "https://www.instagram.com/api/v1/direct_v2/threads/\(escapedID)/?limit=50")!
        let response = try await data(for: request(url: url, instagramSession: instagramSession), instagramSession: instagramSession)
        return InstagramResult(value: try decoder.decode(ThreadResponse.self, from: response.data), session: response.session)
    }

    func send(text: String, to threadID: String, using instagramSession: InstagramSession) async throws -> InstagramSession {
        guard instagramSession.isConfigured else {
            throw InstagramClientError.missingSession
        }

        guard let template = instagramSession.sendTemplate else {
            throw InstagramClientError.missingSendTemplate
        }

        var request = request(url: URL(string: "https://www.instagram.com/api/graphql")!, instagramSession: instagramSession)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("https://www.instagram.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.instagram.com/direct/t/\(threadID)/", forHTTPHeaderField: "Referer")
        request.setValue(template.friendlyName, forHTTPHeaderField: "X-FB-Friendly-Name")
        request.setValue(nil, forHTTPHeaderField: "X-Requested-With")

        if let csrf = instagramSession.csrfToken ?? nonEmpty(template.headers["x-csrftoken"]) {
            request.setValue(csrf, forHTTPHeaderField: "X-CSRFToken")
        }

        if let lsd = template.lsd {
            request.setValue(lsd, forHTTPHeaderField: "X-FB-LSD")
        }

        for header in passthroughHeaders(from: template.headers) {
            request.setValue(header.value, forHTTPHeaderField: header.key)
        }

        let bodyFields = try graphqlSendFields(from: template, text: text, threadID: threadID)
        request.httpBody = encodeForm(bodyFields).data(using: .utf8)

        return try await data(for: request, instagramSession: instagramSession).session
    }

    private func request(url: URL, instagramSession: InstagramSession) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(instagramSession.cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue(instagramSession.appID, forHTTPHeaderField: "X-IG-App-ID")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("https://www.instagram.com/direct/inbox/", forHTTPHeaderField: "Referer")
        request.setValue("https://www.instagram.com", forHTTPHeaderField: "Origin")
        request.setValue(instagramSession.sendTemplate?.headers["user-agent"] ?? UserAgent.desktopChrome, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        return request
    }

    private func data(for request: URLRequest, instagramSession: InstagramSession) async throws -> (data: Data, session: InstagramSession) {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .httpTooManyRedirects {
            throw InstagramClientError.tooManyRedirects
        }

        guard let http = response as? HTTPURLResponse else {
            throw InstagramClientError.invalidResponse
        }

        let updatedSession = instagramSession.merging(response: http)

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data.prefix(240), encoding: .utf8) ?? ""
            throw InstagramClientError.httpStatus(http.statusCode, body)
        }

        return (data, updatedSession)
    }

    private func escapeForm(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func encodeForm(_ fields: [String: String]) -> String {
        fields
            .map { key, value in "\(escapeForm(key))=\(escapeForm(value))" }
            .joined(separator: "&")
    }

    private func graphqlSendFields(from template: GraphQLSendTemplate, text: String, threadID: String) throws -> [String: String] {
        var fields = template.formFields
        fields["fb_api_req_friendly_name"] = "IGDirectTextSendMutation"
        fields["fb_api_caller_class"] = fields["fb_api_caller_class"] ?? "RelayModern"
        fields["server_timestamps"] = fields["server_timestamps"] ?? "true"

        let variablesData = Data((fields["variables"] ?? "{}").utf8)
        var variables = (try JSONSerialization.jsonObject(with: variablesData) as? [String: Any]) ?? [:]
        variables["ig_thread_igid"] = threadID
        variables["offline_threading_id"] = makeOfflineThreadingID()
        variables["text"] = ["sensitive_string_value": text]
        variables["mentions"] = []
        variables["mentioned_user_ids"] = []
        variables["send_attribution"] = "igd_web_chat_tab:in_thread"

        let updatedVariables = try JSONSerialization.data(withJSONObject: variables, options: [.sortedKeys])
        fields["variables"] = String(data: updatedVariables, encoding: .utf8) ?? "{}"
        return fields
    }

    private func passthroughHeaders(from headers: [String: String]) -> [String: String] {
        let allowed = [
            "dnt",
            "priority",
            "sec-ch-ua",
            "sec-ch-ua-full-version-list",
            "sec-ch-ua-mobile",
            "sec-ch-ua-model",
            "sec-ch-ua-platform",
            "sec-ch-ua-platform-version",
            "sec-fetch-dest",
            "sec-fetch-mode",
            "sec-fetch-site",
            "sec-gpc",
            "x-asbd-id",
            "x-ig-max-touch-points"
        ]

        return headers.filter { allowed.contains($0.key.lowercased()) }
    }

    private func makeOfflineThreadingID() -> String {
        String(UInt64.random(in: 1_000_000_000_000_000_000...9_000_000_000_000_000_000))
    }
}

enum UserAgent {
    static let desktopChrome = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36"
}
