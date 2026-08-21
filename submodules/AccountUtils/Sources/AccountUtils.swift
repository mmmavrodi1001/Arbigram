import Foundation
import SwiftSignalKit
import TelegramCore
import TelegramUIPreferences
import AccountContext
import ArbigramSettings

/// ARBIGRAM: hidden accounts are filtered out of every list built from this
/// function, which is the funnel the settings list, the switcher and the fork's
/// own screens all go through. It is not a signal, so it is wrapped into one:
/// typing the phrase has to make the lists rebuild.
private let arbigramHiddenRevealed: Signal<Bool, NoError> = Signal { subscriber in
    subscriber.putNext(ArbigramSettings.shared.hiddenRevealed)
    let observer = NotificationCenter.default.addObserver(forName: ArbigramSettings.changedNotification, object: nil, queue: .main) { _ in
        subscriber.putNext(ArbigramSettings.shared.hiddenRevealed)
    }
    return ActionDisposable {
        NotificationCenter.default.removeObserver(observer)
    }
}
|> distinctUntilChanged

// ARBIGRAM: raised account limits (upstream: 3 / 4)
public let maximumNumberOfAccounts = 30
public let maximumPremiumNumberOfAccounts = 30

public func activeAccountsAndPeers(context: AccountContext, includePrimary: Bool = false, includeHidden: Bool = false) -> Signal<((AccountContext, EnginePeer)?, [(AccountContext, EnginePeer, Int32)]), NoError> {
    let sharedContext = context.sharedContext
    return context.sharedContext.activeAccountContexts
    |> mapToSignal { primary, activeAccounts, _ -> Signal<((AccountContext, EnginePeer)?, [(AccountContext, EnginePeer, Int32)]), NoError> in
        var accounts: [Signal<(AccountContext, EnginePeer, Int32)?, NoError>] = []
        func accountWithPeer(_ context: AccountContext) -> Signal<(AccountContext, EnginePeer, Int32)?, NoError> {
            return combineLatest(context.account.postbox.peerView(id: context.account.peerId), renderedTotalUnreadCount(accountManager: sharedContext.accountManager, engine: context.engine))
            |> map { view, totalUnreadCount -> (EnginePeer?, Int32) in
                return (view.peers[view.peerId].flatMap(EnginePeer.init), totalUnreadCount.0)
            }
            |> distinctUntilChanged { lhs, rhs in
                if lhs.0 != rhs.0 {
                    return false
                }
                if lhs.1 != rhs.1 {
                    return false
                }
                return true
            }
            |> map { peer, totalUnreadCount -> (AccountContext, EnginePeer, Int32)? in
                if let peer = peer {
                    return (context, peer, totalUnreadCount)
                } else {
                    return nil
                }
            }
        }
        for (_, context, _) in activeAccounts {
            accounts.append(accountWithPeer(context))
        }
        
        return combineLatest(combineLatest(accounts), arbigramHiddenRevealed)
        |> map { accounts, hiddenRevealed -> ((AccountContext, EnginePeer)?, [(AccountContext, EnginePeer, Int32)]) in
            var primaryRecord: (AccountContext, EnginePeer)?
            if let first = accounts.filter({ $0?.0.account.id == primary?.account.id }).first, let (account, peer, _) = first {
                primaryRecord = (account, peer)
            }
            var accountRecords: [(AccountContext, EnginePeer, Int32)] = (includePrimary ? accounts : accounts.filter({ $0?.0.account.id != primary?.account.id })).compactMap({ $0 })
            // ARBIGRAM: the account in use is never hidden from itself — you
            // would be looking at a switcher that cannot show where you are.
            if !includeHidden && !hiddenRevealed {
                let meta = ArbigramSettings.shared.accountMeta
                accountRecords = accountRecords.filter { entry in
                    if entry.0.account.id == primary?.account.id {
                        return true
                    }
                    return !(meta[entry.0.account.peerId.id._internalGetInt64Value()]?.hidden ?? false)
                }
            }
            return (primaryRecord, accountRecords)
        }
    }
}
