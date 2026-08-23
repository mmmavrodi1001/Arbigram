import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext
import AccountUtils

/// Every private conversation on an account, as candidates for clearing.
///
/// Only one-to-one chats with people. Groups and channels are left alone
/// because a member cannot remove anyone else's messages there, so "clear for
/// everyone" would quietly mean something different. Bots are left alone
/// because revoking a conversation with a program is theatre. Saved Messages is
/// left alone because there is no everyone.
///
/// The archive is asked for as well: an archived conversation is still a
/// conversation, and a button that says every private chat cannot quietly mean
/// every unarchived one.
func arbigramPrivateChatPeers(context: AccountContext) -> Signal<[EnginePeer], NoError> {
    let lists = combineLatest(
        context.engine.messages.chatList(group: .root, count: 1000) |> take(1),
        context.engine.messages.chatList(group: .archive, count: 1000) |> take(1)
    )
    return lists
    |> map { root, archive -> [EnginePeer] in
        var seen = Set<EnginePeer.Id>()
        var result: [EnginePeer] = []
        for chatList in [root, archive] {
            for item in chatList.items {
                guard case let .user(user) = item.renderedPeer.peer else {
                    continue
                }
                if user.botInfo != nil {
                    continue
                }
                if user.id == context.account.peerId {
                    continue
                }
                if seen.contains(user.id) {
                    continue
                }
                seen.insert(user.id)
                result.append(.user(user))
            }
        }
        return result
    }
}

/// Clears each conversation for both sides, one after another.
///
/// Sequentially rather than all at once: this is a burst of destructive
/// requests, and firing five hundred of them together is how a session gets
/// rate-limited halfway through with no idea what did and did not happen.
func arbigramClearPrivateChats(context: AccountContext, peers: [EnginePeer]) -> Signal<Never, NoError> {
    if peers.isEmpty {
        return .complete()
    }
    var signal: Signal<Never, NoError> = .complete()
    for peer in peers {
        signal = signal
        |> then(
            context.engine.messages.clearHistoryInteractively(peerId: peer.id, threadId: nil, type: .forEveryone)
            |> ignoreValues
        )
    }
    return signal
}

/// The account context for a given user id, including hidden accounts — the
/// screen offering this already knows which account it is describing.
func arbigramAccountContext(context: AccountContext, userId: Int64) -> Signal<AccountContext?, NoError> {
    return activeAccountsAndPeers(context: context, includePrimary: true, includeHidden: true)
    |> take(1)
    |> map { _, accounts -> AccountContext? in
        for (accountContext, _, _) in accounts {
            if accountContext.account.peerId.id._internalGetInt64Value() == userId {
                return accountContext
            }
        }
        return nil
    }
}
