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
func arbigramRecordDeletedMessages(transaction: Transaction, ids: [MessageId]) {
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
        for media in message.media {
            if media is TelegramMediaImage {
                mediaKind = "photo"
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
            deletedAt: now
        ))
    }

    if !records.isEmpty {
        ArbigramCoreSettings.shared.appendDeletedMessages(records)
    }
}

/// The global-id variants of the same updates never name a message directly.
func arbigramRecordDeletedMessagesWithGlobalIds(transaction: Transaction, globalIds: [Int32]) {
    if !ArbigramCoreSettings.shared.keepDeletedMessages {
        return
    }
    arbigramRecordDeletedMessages(transaction: transaction, ids: transaction.messageIdsForGlobalIds(globalIds))
}
