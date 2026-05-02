import AVKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedConversation: Conversation?

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                sidebar
            } detail: {
                detail
            }

            StatusBar()
                .environmentObject(model)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
                .disabled(model.isLoading)

                Button {
                    model.showSessionEditor = true
                } label: {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                }
                .help("Session")
            }
        }
        .sheet(isPresented: $model.showSessionEditor) {
            SessionEditorView()
                .environmentObject(model)
        }
        .sheet(isPresented: $model.showLoginWindow) {
            LoginCaptureView()
                .environmentObject(model)
        }
        .onAppear {
            if model.session.isConfigured {
                model.refresh()
            }
        }
        .onChange(of: selectedConversation) { _, conversation in
            model.select(conversation)
        }
        .onChange(of: model.selectedConversationID) { _, id in
            guard selectedConversation?.id != id else { return }
            selectedConversation = model.conversations.first { $0.id == id }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search", text: $model.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .padding(10)

            List(model.filteredConversations, selection: $selectedConversation) { conversation in
                ConversationRow(conversation: conversation)
                    .tag(conversation)
            }
            .listStyle(.sidebar)
        }
        .navigationTitle("Direct")
        .frame(minWidth: 280)
    }

    @ViewBuilder
    private var detail: some View {
        if let conversation = model.selectedConversation {
            ConversationDetail(conversation: conversation)
                .environmentObject(model)
        } else {
            EmptyStateView()
                .environmentObject(model)
        }
    }
}

struct ConversationRow: View {
    var conversation: Conversation

    var body: some View {
        HStack(spacing: 10) {
            AvatarView(title: conversation.title, url: conversation.avatarURL)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(conversation.title)
                        .font(.callout.weight(conversation.isUnread ? .semibold : .regular))
                        .lineLimit(1)

                    Spacer()

                    if let lastActivity = conversation.lastActivity {
                        Text(lastActivity, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(conversation.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if conversation.isUnread {
                Circle()
                    .fill(.blue)
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ConversationDetail: View {
    @EnvironmentObject private var model: AppModel
    var conversation: Conversation

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: model.messages) { _, messages in
                    guard let last = messages.last else { return }
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }

            Divider()

            composer
        }
        .navigationTitle(conversation.title)
    }

    private var header: some View {
        HStack(spacing: 10) {
            AvatarView(title: conversation.title, url: conversation.avatarURL)
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(conversation.users.compactMap(\.username).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message", text: $model.draftText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .onSubmit {
                    model.sendDraft()
                }

            Button {
                model.sendDraft()
            } label: {
                Image(systemName: "paperplane.fill")
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!model.canSend)
            .help("Send")
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct MessageBubble: View {
    var message: Message

    var body: some View {
        HStack {
            if message.isFromViewer {
                Spacer(minLength: 80)
            }

            VStack(alignment: message.isFromViewer ? .trailing : .leading, spacing: 4) {
                if !message.isFromViewer {
                    Text(message.senderName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: message.isFromViewer ? .trailing : .leading, spacing: 6) {
                    AttachmentGroupView(attachments: message.attachments)

                    if nonEmpty(message.text) != nil || message.attachments.isEmpty {
                        Text(message.text)
                            .textSelection(.enabled)
                            .font(.body)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundStyle(message.isFromViewer ? .white : .primary)
                            .background(message.isFromViewer ? Color.accentColor : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                if let timestamp = message.timestamp {
                    Text(timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if !message.isFromViewer {
                Spacer(minLength: 80)
            }
        }
    }
}

struct AttachmentGroupView: View {
    var attachments: [MessageAttachment]

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        if attachments.count <= 1 {
            ForEach(attachments) { attachment in
                AttachmentView(attachment: attachment)
                    .frame(maxWidth: 360)
            }
        } else {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(attachments) { attachment in
                    AttachmentView(attachment: attachment, compact: true)
                        .frame(width: 177, height: 177)
                }
            }
            .frame(width: 360)
        }
    }
}

struct AttachmentView: View {
    var attachment: MessageAttachment
    var compact = false

    var body: some View {
        switch attachment.kind {
        case .image:
            image
        case .video:
            video
        case .post:
            post
        case .voice:
            attachmentLabel("Voice message", icon: "waveform")
        case .unknown:
            attachmentLabel("Attachment", icon: "paperclip")
        }
    }

    private var image: some View {
        Group {
            if let url = attachment.url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        attachmentLabel("Image unavailable", icon: "photo")
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    @unknown default:
                        attachmentLabel("Image", icon: "photo")
                    }
                }
            } else {
                attachmentLabel("Image", icon: "photo")
            }
        }
        .aspectRatio(compact ? 1 : attachment.aspectRatio, contentMode: compact ? .fill : .fit)
        .frame(maxHeight: compact ? 177 : 420)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var video: some View {
        Group {
            if let url = attachment.url {
                VideoPlayer(player: AVPlayer(url: url))
            } else {
                attachmentLabel("Video", icon: "play.rectangle")
            }
        }
        .aspectRatio(compact ? 1 : attachment.aspectRatio, contentMode: compact ? .fill : .fit)
        .frame(maxHeight: compact ? 177 : 420)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var post: some View {
        Group {
            if let url = attachment.url {
                Link(destination: url) {
                    postCard
                }
                .buttonStyle(.plain)
            } else {
                postCard
            }
        }
        .frame(maxWidth: compact ? 177 : 360)
    }

    private var postCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let previewURL = attachment.previewURL {
                AsyncImage(url: previewURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        postPlaceholder
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: compact ? 118 : 190)
                    @unknown default:
                        postPlaceholder
                    }
                }
                .frame(height: compact ? 118 : 190)
                .clipped()
            } else {
                postPlaceholder
                    .frame(height: compact ? 118 : 150)
            }

            VStack(alignment: .leading, spacing: 4) {
                Label(attachment.title ?? "Instagram post", systemImage: "square.on.square")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)

                if let subtitle = nonEmpty(attachment.subtitle) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(compact ? 1 : 2)
                } else if let url = attachment.url {
                    Text(url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(10)
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var postPlaceholder: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)

            Image(systemName: "photo.on.rectangle")
                .font(.system(size: compact ? 24 : 34))
                .foregroundStyle(.secondary)
        }
    }

    private func attachmentLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct AvatarView: View {
    var title: String
    var url: URL?

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(nsColor: .controlAccentColor).opacity(0.18))

            if let url {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    initials
                }
                .clipShape(Circle())
            } else {
                initials
            }
        }
    }

    private var initials: some View {
        Text(String(title.prefix(1)).uppercased())
            .font(.headline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

struct EmptyStateView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: model.session.isConfigured ? "tray" : "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)

            Text(model.session.isConfigured ? "No Conversation Selected" : "Instagram Session Required")
                .font(.title3.weight(.semibold))

            Button(model.session.isConfigured ? "Refresh" : "Session") {
                if model.session.isConfigured {
                    model.refresh()
                } else {
                    model.showSessionEditor = true
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StatusBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.isLoading ? Color.orange : Color.green)
                .frame(width: 8, height: 8)

            Text(model.statusText)
                .lineLimit(1)

            Spacer()

            Text("\(model.conversations.count) conversations")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
    }
}

struct SessionEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var cookieHeader = ""
    @State private var appID = InstagramSession.empty.appID

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Instagram Session")
                .font(.title3.weight(.semibold))

            TextField("X-IG-App-ID", text: $appID)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Label(model.session.sendTemplate == nil ? "No send template" : "Send template ready", systemImage: model.session.sendTemplate == nil ? "exclamationmark.triangle" : "checkmark.circle")
                    .foregroundStyle(model.session.sendTemplate == nil ? Color.secondary : Color.green)

                Spacer()

                Button("Login Window...") {
                    model.showLoginWindow = true
                }

                Button("Import HAR...") {
                    importHAR()
                }
            }

            TextEditor(text: $cookieHeader)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 140)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor))
                }

            HStack {
                Button("Sign Out", role: .destructive) {
                    model.signOut()
                    dismiss()
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    model.saveSession(cookieHeader: cookieHeader, appID: appID)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(nonEmpty(cookieHeader) == nil)
            }
        }
        .padding(18)
        .frame(width: 560)
        .onAppear {
            cookieHeader = model.session.cookieHeader
            appID = model.session.appID
        }
    }

    private func importHAR() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "har") ?? .json, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose a HAR file containing a successful Instagram send request."

        if panel.runModal() == .OK, let url = panel.url {
            model.importHAR(from: url)
            appID = model.session.appID
        }
    }
}

struct LoginCaptureView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var captureTrigger = 0
    @State private var statusText = "Loading Instagram"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "lock.square")
                    .foregroundStyle(.secondary)

                Text(statusText)
                    .lineLimit(1)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Use This Session") {
                    captureTrigger += 1
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
            .background(.bar)

            AuthWebView(captureTrigger: $captureTrigger) { result in
                model.applyAuthCapture(result)
                dismiss()
            } onStatus: { status in
                statusText = status
            }
        }
        .frame(width: 940, height: 720)
    }
}
