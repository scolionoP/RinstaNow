import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var messages: [Message] = []
    @Published var selectedConversationID: String?
    @Published var session: InstagramSession
    @Published var draftText = ""
    @Published var searchText = ""
    @Published var isLoading = false
    @Published var statusText = "Ready"
    @Published var showSessionEditor = false
    @Published var showLoginWindow = false

    private let client = InstagramClient()
    private let sessionStore = SessionStore()

    init() {
        self.session = sessionStore.load()
        self.showSessionEditor = !session.isConfigured
    }

    var selectedConversation: Conversation? {
        conversations.first { $0.id == selectedConversationID }
    }

    var filteredConversations: [Conversation] {
        guard let query = nonEmpty(searchText)?.localizedLowercase else {
            return conversations
        }

        return conversations.filter { conversation in
            conversation.title.localizedLowercase.contains(query) ||
                conversation.subtitle.localizedLowercase.contains(query)
        }
    }

    var canSend: Bool {
        selectedConversationID != nil && nonEmpty(draftText) != nil && !isLoading
    }

    func refresh() {
        Task {
            await loadInbox()
        }
    }

    func saveSession(cookieHeader: String, appID: String) {
        session = InstagramSession(
            cookieHeader: cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines),
            appID: nonEmpty(appID) ?? InstagramSession.empty.appID,
            sendTemplate: session.sendTemplate
        )
        sessionStore.save(session)
        showSessionEditor = false
        refresh()
    }

    func importHAR(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let template = try HARImporter().importSendTemplate(from: data)
            session.sendTemplate = template
            session.appID = template.headers["x-ig-app-id"] ?? session.appID
            sessionStore.save(session)
            statusText = "Imported send template"
        } catch {
            statusText = error.localizedDescription
        }
    }

    func applyAuthCapture(_ result: AuthCaptureResult) {
        let cookieHeader = nonEmpty(result.cookieHeader) ?? session.cookieHeader
        var updatedSession = InstagramSession(
            cookieHeader: cookieHeader,
            appID: nonEmpty(result.snapshot.appID) ?? session.appID,
            sendTemplate: nil
        )
        updatedSession.sendTemplate = GraphQLSendTemplate.webBootstrap(snapshot: result.snapshot, session: updatedSession)
        session = updatedSession
        sessionStore.save(updatedSession)
        statusText = "Captured browser session"
        showLoginWindow = false
        showSessionEditor = false
        refresh()
    }

    func signOut() {
        session = .empty
        sessionStore.clear()
        conversations = []
        messages = []
        selectedConversationID = nil
        statusText = "Signed out"
        showSessionEditor = true
    }

    func select(_ conversation: Conversation?) {
        selectedConversationID = conversation?.id
        messages = []

        guard conversation != nil else { return }

        Task {
            await loadSelectedThread()
        }
    }

    func sendDraft() {
        guard let threadID = selectedConversationID,
              let text = nonEmpty(draftText) else {
            return
        }

        draftText = ""

        Task {
            await send(text: text, threadID: threadID)
        }
    }

    private func loadInbox() async {
        isLoading = true
        statusText = "Refreshing"

        do {
            let response = try await client.fetchInbox(using: session)
            applySessionUpdate(response.session)

            let threads = response.value.inbox?.threads ?? []
            conversations = threads
                .map { $0.conversation() }
                .sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }

            if selectedConversationID == nil {
                selectedConversationID = conversations.first?.id
            }

            statusText = conversations.isEmpty ? "No conversations" : "Updated \(Date.now.formatted(date: .omitted, time: .shortened))"
            isLoading = false

            if selectedConversationID != nil {
                await loadSelectedThread()
            }
        } catch {
            isLoading = false
            statusText = error.localizedDescription
            if case InstagramClientError.missingSession = error {
                showSessionEditor = true
            }
        }
    }

    private func loadSelectedThread() async {
        guard let threadID = selectedConversationID else { return }

        isLoading = true

        do {
            let response = try await client.fetchThread(id: threadID, using: session)
            applySessionUpdate(response.session)
            messages = response.value.thread?.messages() ?? []
            isLoading = false
        } catch {
            isLoading = false
            statusText = error.localizedDescription
        }
    }

    private func send(text: String, threadID: String) async {
        isLoading = true
        statusText = "Sending"

        do {
            let updatedSession = try await client.send(text: text, to: threadID, using: session)
            applySessionUpdate(updatedSession)
            statusText = "Sent"
            await loadSelectedThread()
            await loadInbox()
        } catch {
            isLoading = false
            statusText = error.localizedDescription
            draftText = text
        }
    }

    private func applySessionUpdate(_ updatedSession: InstagramSession) {
        guard updatedSession != session else { return }
        session = updatedSession
        sessionStore.save(updatedSession)
    }
}

final class SessionStore {
    private let key = "instagram-session"

    func load() -> InstagramSession {
        guard let data = UserDefaults.standard.data(forKey: key),
              let session = try? JSONDecoder().decode(InstagramSession.self, from: data) else {
            return .empty
        }

        return session
    }

    func save(_ session: InstagramSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
