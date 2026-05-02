import Foundation

struct Conversation: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var subtitle: String
    var avatarURL: URL?
    var lastActivity: Date?
    var isUnread: Bool
    var users: [IGUser]
}

struct Message: Identifiable, Hashable, Sendable {
    let id: String
    var senderID: String?
    var senderName: String
    var text: String
    var timestamp: Date?
    var isFromViewer: Bool
    var attachments: [MessageAttachment]
}

struct MessageAttachment: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case image
        case video
        case post
        case voice
        case unknown
    }

    let id = UUID()
    var kind: Kind
    var url: URL?
    var previewURL: URL?
    var title: String?
    var subtitle: String?
    var width: Int?
    var height: Int?

    var aspectRatio: Double {
        guard let width, let height, height > 0 else {
            return kind == .video ? 16.0 / 9.0 : 4.0 / 5.0
        }

        return Double(width) / Double(height)
    }
}

struct IGUser: Codable, Hashable, Sendable {
    var pk: String?
    var pkID: String?
    var username: String?
    var fullName: String?
    var profilePicURL: String?

    enum CodingKeys: String, CodingKey {
        case pk
        case pkID = "pk_id"
        case username
        case fullName = "full_name"
        case profilePicURL = "profile_pic_url"
    }

    var id: String {
        pk ?? pkID ?? username ?? UUID().uuidString
    }

    var displayName: String {
        if let fullName, !fullName.isEmpty {
            return fullName
        }

        return username ?? "Instagram User"
    }
}

struct InboxResponse: Decodable, Sendable {
    var inbox: Inbox?
    var status: String?
}

struct Inbox: Decodable, Sendable {
    var threads: [ThreadSummary]?
    var unseenCount: Int?

    enum CodingKeys: String, CodingKey {
        case threads
        case unseenCount = "unseen_count"
    }
}

struct ThreadResponse: Decodable, Sendable {
    var thread: ThreadSummary?
    var status: String?
}

struct ThreadSummary: Decodable, Sendable {
    var threadID: String
    var threadTitle: String?
    var users: [IGUser]?
    var items: [ThreadItem]?
    var lastActivityAt: Int64?
    var readState: Int?
    var viewerID: String?

    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case threadTitle = "thread_title"
        case users
        case items
        case lastActivityAt = "last_activity_at"
        case readState = "read_state"
        case viewerID = "viewer_id"
    }

    func conversation() -> Conversation {
        let participants = users ?? []
        let fallbackTitle = participants.map(\.displayName).joined(separator: ", ")
        let latest = items?.first
        let avatar = participants.compactMap { $0.profilePicURL }.first.flatMap(URL.init(string:))

        return Conversation(
            id: threadID,
            title: nonEmpty(threadTitle) ?? nonEmpty(fallbackTitle) ?? "Conversation",
            subtitle: latest?.previewText ?? "",
            avatarURL: avatar,
            lastActivity: millisecondsToDate(lastActivityAt),
            isUnread: readState == 1,
            users: participants
        )
    }

    func messages() -> [Message] {
        let userNames = Dictionary(uniqueKeysWithValues: (users ?? []).map { ($0.id, $0.displayName) })
        let viewer = viewerID

        return (items ?? [])
            .reversed()
            .map { item in
                let senderID = item.userID
                let name = senderID.flatMap { userNames[$0] } ?? "Instagram User"

                return Message(
                    id: item.itemID ?? UUID().uuidString,
                    senderID: senderID,
                    senderName: name,
                    text: item.messageText,
                    timestamp: microsecondsToDate(item.timestamp),
                    isFromViewer: senderID != nil && senderID == viewer,
                    attachments: item.attachments
                )
            }
    }
}

struct ThreadItem: Decodable, Sendable {
    var itemID: String?
    var userID: String?
    var timestamp: Int64?
    var itemType: String?
    var text: String?
    var link: LinkPayload?
    var media: MediaPayload?
    var mediaShare: MediaPayload?
    var visualMedia: VisualMediaPayload?
    var voiceMedia: VoiceMediaPayload?
    var actionLog: ActionLogPayload?

    enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case userID = "user_id"
        case timestamp
        case itemType = "item_type"
        case text
        case link
        case media
        case mediaShare = "media_share"
        case visualMedia = "visual_media"
        case voiceMedia = "voice_media"
        case actionLog = "action_log"
    }

    var previewText: String {
        if let text = nonEmpty(text) {
            return text
        }

        if let linkText = nonEmpty(link?.text) {
            return linkText
        }

        if media != nil || mediaShare != nil || visualMedia != nil {
            return "Photo or video"
        }

        if voiceMedia != nil {
            return "Voice message"
        }

        if let description = nonEmpty(actionLog?.description) {
            return description
        }

        return itemType?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Message"
    }

    var messageText: String {
        if let text = nonEmpty(text) {
            return text
        }

        if let linkText = nonEmpty(link?.text) {
            return linkText
        }

        if let description = nonEmpty(actionLog?.description) {
            return description
        }

        return ""
    }

    var attachments: [MessageAttachment] {
        var attachments: [MessageAttachment] = []

        if let postAttachment = mediaShare?.postAttachment {
            attachments.append(postAttachment)
        }

        for mediaPayload in mediaPayloads.flatMap(\.flattenedMedia) {
            if let video = mediaPayload.bestVideoURL {
                attachments.append(
                    MessageAttachment(
                        kind: .video,
                        url: video,
                        previewURL: mediaPayload.bestImageURL,
                        title: nil,
                        subtitle: nil,
                        width: mediaPayload.bestImageWidth,
                        height: mediaPayload.bestImageHeight
                    )
                )
            } else if let image = mediaPayload.bestImageURL {
                attachments.append(
                    MessageAttachment(
                        kind: .image,
                        url: image,
                        previewURL: nil,
                        title: nil,
                        subtitle: nil,
                        width: mediaPayload.bestImageWidth,
                        height: mediaPayload.bestImageHeight
                    )
                )
            } else {
                attachments.append(MessageAttachment(kind: .unknown, url: nil, previewURL: nil, title: nil, subtitle: nil, width: nil, height: nil))
            }
        }

        if let audioURL = voiceMedia?.media?.audio?.audioSource.flatMap(URL.init(string:)) {
            attachments.append(MessageAttachment(kind: .voice, url: audioURL, previewURL: nil, title: nil, subtitle: nil, width: nil, height: nil))
        }

        return attachments
    }

    private var mediaPayloads: [MediaPayload] {
        [media, mediaShare?.postAttachment == nil ? mediaShare : nil, visualMedia?.media].compactMap { $0 }
    }
}

struct LinkPayload: Decodable, Sendable {
    var text: String?
}

struct MediaPayload: Decodable, Sendable {
    var imageVersions2: ImageVersions?
    var videoVersions: [VideoVersion]?
    var carouselMedia: [MediaPayload]?
    var code: String?
    var caption: CaptionPayload?
    var user: IGUser?
    var productType: String?
    var originalWidth: Int?
    var originalHeight: Int?

    enum CodingKeys: String, CodingKey {
        case imageVersions2 = "image_versions2"
        case videoVersions = "video_versions"
        case carouselMedia = "carousel_media"
        case code
        case caption
        case user
        case productType = "product_type"
        case originalWidth = "original_width"
        case originalHeight = "original_height"
    }

    var bestImageURL: URL? {
        imageVersions2?.candidates?.first?.url.flatMap(URL.init(string:))
    }

    var bestImageWidth: Int? {
        imageVersions2?.candidates?.first?.width ?? originalWidth
    }

    var bestImageHeight: Int? {
        imageVersions2?.candidates?.first?.height ?? originalHeight
    }

    var bestVideoURL: URL? {
        videoVersions?.first?.url.flatMap(URL.init(string:))
    }

    var flattenedMedia: [MediaPayload] {
        if let carouselMedia, !carouselMedia.isEmpty {
            return carouselMedia.flatMap(\.flattenedMedia)
        }

        return [self]
    }

    var permalink: URL? {
        guard let code = nonEmpty(code) else { return nil }
        return URL(string: "https://www.instagram.com/p/\(code)/")
    }

    var postAttachment: MessageAttachment? {
        guard let permalink else { return nil }

        let title = user?.username.map { "@\($0)" } ?? "Instagram post"
        let subtitle = nonEmpty(caption?.text) ?? nonEmpty(productType?.replacingOccurrences(of: "_", with: " ").capitalized)

        return MessageAttachment(
            kind: .post,
            url: permalink,
            previewURL: bestImageURL ?? carouselMedia?.compactMap(\.bestImageURL).first,
            title: title,
            subtitle: subtitle,
            width: bestImageWidth ?? carouselMedia?.compactMap(\.bestImageWidth).first,
            height: bestImageHeight ?? carouselMedia?.compactMap(\.bestImageHeight).first
        )
    }
}

struct CaptionPayload: Decodable, Sendable {
    var text: String?
}

struct ImageVersions: Decodable, Sendable {
    var candidates: [ImageCandidate]?
}

struct ImageCandidate: Decodable, Sendable {
    var url: String?
    var width: Int?
    var height: Int?
}

struct VideoVersion: Decodable, Sendable {
    var url: String?
    var width: Int?
    var height: Int?
}

struct VisualMediaPayload: Decodable, Sendable {
    var media: MediaPayload?
}

struct VoiceMediaPayload: Decodable, Sendable {
    var media: VoiceMediaContainer?
}

struct VoiceMediaContainer: Decodable, Sendable {
    var audio: AudioPayload?
}

struct AudioPayload: Decodable, Sendable {
    var audioSource: String?

    enum CodingKeys: String, CodingKey {
        case audioSource = "audio_src"
    }
}

struct ActionLogPayload: Decodable, Sendable {
    var description: String?
}

func nonEmpty(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

func millisecondsToDate(_ value: Int64?) -> Date? {
    guard let value else { return nil }
    return Date(timeIntervalSince1970: TimeInterval(value) / 1_000)
}

func microsecondsToDate(_ value: Int64?) -> Date? {
    guard let value else { return nil }
    return Date(timeIntervalSince1970: TimeInterval(value) / 1_000_000)
}
