import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext
import AccountUtils
import ArbigramSettings

/// Telegram's own service bot. It is the only thing that will say whether an
/// account is under a spam limit — the state exists nowhere in the API, only in
/// a sentence this bot writes when asked.
private let arbigramSpamBotUsername = "SpamBot"

/// Long enough for a bot that occasionally takes its time, short enough that
/// thirty accounts do not turn into an afternoon.
private let arbigramSpamReplyTimeout: Double = 25.0

/// Ask one account's spam bot and read the answer back.
///
/// Sending is the easy half. There is no "get me the reply" call, so the answer
/// is picked out of the chat list: the bot's conversation carries its latest
/// message, and the view is live, so waiting on it is waiting on the reply.
/// A few seconds of slack on the timestamp covers clock skew between the phone
/// and the server without letting a reply from last week count as this one.
func arbigramCheckSpamStatus(context: AccountContext) -> Signal<ArbigramSpamStatus, NoError> {
    let askedAt = Int32(Date().timeIntervalSince1970)

    return context.engine.peers.resolvePeerByName(name: arbigramSpamBotUsername, referrer: nil)
    |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
        switch result {
        case .progress:
            return .complete()
        case let .result(peer):
            return .single(peer)
        }
    }
    |> take(1)
    |> mapToSignal { peer -> Signal<ArbigramSpamStatus, NoError> in
        guard let peer else {
            return .single(ArbigramSpamStatus(state: .unknown, checkedAt: askedAt))
        }

        let send = enqueueMessages(account: context.account, peerId: peer.id, messages: [
            .message(
                text: "/start",
                attributes: [],
                inlineStickers: [:],
                mediaReference: nil,
                threadId: nil,
                replyToMessageId: nil,
                replyToStoryId: nil,
                localGroupingKey: nil,
                correlationId: nil,
                bubbleUpEmojiOrStickersets: []
            )
        ])
        // Typed as the reply rather than dropped to Never: `then` needs both
        // sides to carry the same value, and a send that emits nothing still
        // has to agree about what it is not emitting.
        |> mapToSignal { _ -> Signal<ArbigramSpamStatus, NoError> in
            return .complete()
        }

        // The archive is asked for too: a conversation with a service bot is
        // exactly the kind a tidy person archives, and an archived chat is
        // absent from the root list entirely.
        let lists = combineLatest(
            context.engine.messages.chatList(group: .root, count: 50),
            context.engine.messages.chatList(group: .archive, count: 50)
        )

        let reply = lists
        |> mapToSignal { root, archive -> Signal<ArbigramSpamStatus, NoError> in
            for chatList in [root, archive] {
                for item in chatList.items where item.renderedPeer.peerId == peer.id {
                    for message in item.messages {
                        guard message.flags.contains(.Incoming), !message.text.isEmpty else {
                            continue
                        }
                        if message.timestamp >= askedAt - 5 {
                            return .single(ArbigramSpamStatus.parse(message.text, at: message.timestamp))
                        }
                    }
                }
            }
            return .complete()
        }
        |> take(1)
        |> timeout(
            arbigramSpamReplyTimeout,
            queue: Queue.mainQueue(),
            alternate: .single(ArbigramSpamStatus(state: .unknown, checkedAt: askedAt))
        )

        return send |> then(reply)
    }
}

/// Walk every logged-in account, hidden ones included, and record what the bot
/// says about each. Emits after each account so the list can fill in as it goes
/// rather than sitting blank for a minute.
///
/// The accounts are asked one at a time with a pause between them. Thirty
/// accounts firing the same command at the same service within a second is a
/// pattern worth not making, and the wait costs nothing that matters here.
func arbigramCheckAllSpamStatuses(context: AccountContext, gap: Double = 2.0) -> Signal<(Int64, ArbigramSpamStatus), NoError> {
    return activeAccountsAndPeers(context: context, includePrimary: true, includeHidden: true)
    |> take(1)
    |> mapToSignal { _, accounts -> Signal<(Int64, ArbigramSpamStatus), NoError> in
        var signal: Signal<(Int64, ArbigramSpamStatus), NoError> = .complete()
        for (index, entry) in accounts.enumerated() {
            let accountContext = entry.0
            let userId = accountContext.account.peerId.id._internalGetInt64Value()

            var step = arbigramCheckSpamStatus(context: accountContext)
            |> map { status -> (Int64, ArbigramSpamStatus) in
                ArbigramSettings.shared.setSpamStatus(status, for: userId)
                return (userId, status)
            }
            if index > 0 {
                step = (.complete() |> delay(gap, queue: Queue.mainQueue())) |> then(step)
            }
            signal = signal |> then(step)
        }
        return signal
    }
}
