import Foundation
import Postbox
import ArbigramCore

/// Copies a message out before the postbox loses it.
///
/// The message is still deleted. Keeping it in place would mean inventing a
/// tombstone the whole app has to understand — unread counts, replies, history
/// cleanup, search — and getting any of that wrong breaks chats that work
/// today. A copy costs nothing and answers the question that is actually being
/// asked: what did it say before it went.
///
/// Only incoming messages are recorded. Deleting your own message is a decision
/// you made, and logging it would turn a fork feature into a hoarder.
func arbigramRecordDeletedMessages(transaction: Transaction, mediaBox: MediaBox, ids: [MessageId]) {
    if !ArbigramCoreSettings.shared.keepDeletedMessages {
        return
    }

    var records: [ArbigramDeletedMessage] = []
    let now = Int32(Date().timeIntervalSince1970)

    for id in ids {
        guard let message = transaction.getMessage(id) else {
            continue
        }
        guard message.flags.contains(.Incoming) else {
            continue
        }

        var mediaKind = ""
        var mediaResource: MediaResource?
        var mediaExtension = "dat"

        for media in message.media {
            if let image = media as? TelegramMediaImage {
                mediaKind = "photo"
                mediaResource = image.representations.last?.resource
                mediaExtension = "jpg"
            } else if let file = media as? TelegramMediaFile {
                if file.isVoice {
                    mediaKind = "voice"
                } else if file.isInstantVideo {
                    mediaKind = "round"
                } else if file.isVideo {
                    mediaKind = "video"
                } else if file.isSticker {
                    mediaKind = "sticker"
                } else {
                    mediaKind = "file"
                }
                mediaResource = file.resource
                if let fileName = file.fileName, !(fileName as NSString).pathExtension.isEmpty {
                    mediaExtension = (fileName as NSString).pathExtension
                } else {
                    mediaExtension = arbigramExtension(forMimeType: file.mimeType)
                }
            } else if media is TelegramMediaContact {
                mediaKind = "contact"
            } else if media is TelegramMediaMap {
                mediaKind = "location"
            }
            if !mediaKind.isEmpty {
                break
            }
        }

        // Nothing to remember: no text and nothing to name.
        if message.text.isEmpty && mediaKind.isEmpty {
            continue
        }

        // The file is only there if it was downloaded before the delete
        // arrived. Nothing is fetched here — a deletion is the wrong moment to
        // start pulling bytes off the network for a message that is going away.
        var mediaFile: String?
        if let mediaResource,
           let sourcePath = mediaBox.completedResourcePath(mediaResource),
           let directory = ArbigramCoreSettings.shared.deletedMediaDirectory {
            let name = "\(id.peerId.id._internalGetInt64Value())_\(id.id)_\(now).\(mediaExtension)"
            let destination = directory.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: destination)
            if (try? FileManager.default.copyItem(atPath: sourcePath, toPath: destination.path)) != nil {
                mediaFile = name
            }
        }

        let chatTitle = transaction.getPeer(id.peerId)?.debugDisplayTitle ?? ""
        var authorTitle = ""
        if let authorId = message.author?.id, authorId != id.peerId {
            authorTitle = transaction.getPeer(authorId)?.debugDisplayTitle ?? ""
        }

        records.append(ArbigramDeletedMessage(
            chatId: id.peerId.id._internalGetInt64Value(),
            chatTitle: chatTitle,
            authorTitle: authorTitle,
            text: message.text,
            mediaKind: mediaKind,
            timestamp: message.timestamp,
            deletedAt: now,
            mediaFile: mediaFile
        ))
    }

    if !records.isEmpty {
        ArbigramCoreSettings.shared.appendDeletedMessages(records)
    }
}

/// The global-id variants of the same updates never name a message directly.
func arbigramRecordDeletedMessagesWithGlobalIds(transaction: Transaction, mediaBox: MediaBox, globalIds: [Int32]) {
    if !ArbigramCoreSettings.shared.keepDeletedMessages {
        return
    }
    arbigramRecordDeletedMessages(transaction: transaction, mediaBox: mediaBox, ids: transaction.messageIdsForGlobalIds(globalIds))
}

private func arbigramExtension(forMimeType mimeType: String) -> String {
    switch mimeType {
    case "image/jpeg":
        return "jpg"
    case "image/png":
        return "png"
    case "image/gif":
        return "gif"
    case "image/webp":
        return "webp"
    case "video/mp4":
        return "mp4"
    case "video/quicktime":
        return "mov"
    case "audio/ogg":
        return "ogg"
    case "audio/mpeg":
        return "mp3"
    case "audio/mp4":
        return "m4a"
    case "application/pdf":
        return "pdf"
    default:
        return "dat"
    }
}
