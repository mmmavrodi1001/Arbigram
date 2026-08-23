import Foundation
import UserNotifications
import ArbigramSettings

/// Raises a local notification when the other side deletes something.
///
/// Without it the record is only ever seen by opening the list and looking,
/// which is the wrong way round: the interesting moment is when it happens.
/// It is a local notification rather than a message into Saved Messages
/// because nothing should leave the device for this — the record exists
/// precisely because something was withdrawn.
func arbigramAnnounceDeletedMessages(_ records: [ArbigramDeletedMessage], isRussian: Bool) {
    if records.isEmpty {
        return
    }

    let center = UNUserNotificationCenter.current()
    // One notification per batch. A chat cleared of fifty messages should not
    // arrive as fifty banners.
    let content = UNMutableNotificationContent()

    if records.count == 1, let record = records[0] as ArbigramDeletedMessage? {
        var who = record.chatTitle
        if !record.authorTitle.isEmpty && record.authorTitle != record.chatTitle {
            who = record.authorTitle + " · " + record.chatTitle
        }
        content.title = isRussian ? "Удалено: \(who)" : "Deleted: \(who)"

        var body = record.text
        if !record.mediaKind.isEmpty {
            let kind = "[" + record.mediaKind + "]"
            body = body.isEmpty ? kind : kind + " " + body
        }
        content.body = body
    } else {
        let chats = Set(records.map { $0.chatTitle }).sorted()
        content.title = isRussian ? "Удалено сообщений: \(records.count)" : "\(records.count) messages deleted"
        content.body = chats.joined(separator: ", ")
    }

    content.sound = nil

    let request = UNNotificationRequest(
        identifier: "arbigram.deleted.\(records[0].deletedAt).\(records[0].chatId)",
        content: content,
        trigger: nil
    )
    center.add(request, withCompletionHandler: nil)
}
