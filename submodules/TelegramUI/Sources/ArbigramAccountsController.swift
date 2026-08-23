import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import ItemListUI
import ItemListPeerItem
import PresentationDataUtils
import AccountContext
import AccountUtils
import PeerInfoScreen
import UndoUI
import ArbigramSettings

private let arbigramAccountsSectionPinned: ItemListSectionId = 0
private let arbigramAccountsSectionOther: ItemListSectionId = 1

/// Telegram already stores an order per account record — the iOS app just never
/// offered a way to change it. Writing it here means the new order is the real
/// one, and every list that shows accounts follows.
///
/// Records the screen did not show — hidden accounts — keep their relative
/// order and go after the visible ones. Numbering only what is on screen would
/// leave the hidden ones holding indices that now belong to somebody else, and
/// they would land in the middle of the list the next time they appeared.
private func applyArbigramAccountOrder(context: AccountContext, orderedIds: [AccountRecordId]) -> Signal<Never, NoError> {
    return context.sharedContext.accountManager.transaction { transaction -> Void in
        func currentOrder(_ record: AccountRecord<TelegramAccountManagerTypes.Attribute>) -> Int32 {
            for attribute in record.attributes {
                if case let .sortOrder(sortOrder) = attribute {
                    return sortOrder.order
                }
            }
            return 0
        }

        let listed = Set(orderedIds)
        let trailing = transaction.getRecords()
            .filter { !listed.contains($0.id) }
            .sorted { currentOrder($0) < currentOrder($1) }
            .map { $0.id }

        for (index, id) in (orderedIds + trailing).enumerated() {
            transaction.updateRecord(id, { record in
                guard let record else {
                    return nil
                }
                var attributes = record.attributes.filter { attribute in
                    if case .sortOrder = attribute {
                        return false
                    }
                    return true
                }
                attributes.append(.sortOrder(AccountSortOrderAttribute(order: Int32(index))))
                return AccountRecord(id: record.id, attributes: attributes, temporarySessionId: record.temporarySessionId)
            })
        }
    }
    |> ignoreValues
}

private struct ArbigramAccountRow: Equatable {
    let recordId: AccountRecordId
    let userId: Int64
    let peer: EnginePeer
    let meta: ArbigramAccountMeta
    let unreadCount: Int32

    static func ==(lhs: ArbigramAccountRow, rhs: ArbigramAccountRow) -> Bool {
        return lhs.recordId == rhs.recordId && lhs.userId == rhs.userId && lhs.peer == rhs.peer && lhs.meta == rhs.meta && lhs.unreadCount == rhs.unreadCount
    }
}

private final class ArbigramAccountsArguments {
    let context: AccountContext
    let openAccount: (Int64) -> Void
    let togglePinned: (Int64) -> Void
    let setRevealed: (EnginePeer.Id?) -> Void
    let toggleSelected: (Int64) -> Void

    init(context: AccountContext, openAccount: @escaping (Int64) -> Void, togglePinned: @escaping (Int64) -> Void, setRevealed: @escaping (EnginePeer.Id?) -> Void, toggleSelected: @escaping (Int64) -> Void) {
        self.context = context
        self.openAccount = openAccount
        self.togglePinned = togglePinned
        self.setRevealed = setRevealed
        self.toggleSelected = toggleSelected
    }
}

private enum ArbigramAccountsEntry: ItemListNodeEntry {
    case pinnedHeader(String)
    case otherHeader(String)
    case account(index: Int, pinned: Bool, row: ArbigramAccountRow, editing: Bool, revealed: Bool, selected: Bool?, context: AccountContext)
    case info(String)

    var section: ItemListSectionId {
        switch self {
        case .pinnedHeader:
            return arbigramAccountsSectionPinned
        case let .account(_, pinned, _, _, _, _, _):
            return pinned ? arbigramAccountsSectionPinned : arbigramAccountsSectionOther
        case .otherHeader, .info:
            return arbigramAccountsSectionOther
        }
    }

    var stableId: Int32 {
        switch self {
        case .pinnedHeader:
            return 0
        case .otherHeader:
            return 1
        case let .account(index, _, _, _, _, _, _):
            return Int32(100 + index)
        case .info:
            return 10000
        }
    }

    static func ==(lhs: ArbigramAccountsEntry, rhs: ArbigramAccountsEntry) -> Bool {
        switch lhs {
        case let .pinnedHeader(text):
            if case .pinnedHeader(text) = rhs {
                return true
            }
            return false
        case let .otherHeader(text):
            if case .otherHeader(text) = rhs {
                return true
            }
            return false
        case let .info(text):
            if case .info(text) = rhs {
                return true
            }
            return false
        case let .account(lhsIndex, lhsPinned, lhsRow, lhsEditing, lhsRevealed, lhsSelected, _):
            if case let .account(rhsIndex, rhsPinned, rhsRow, rhsEditing, rhsRevealed, rhsSelected, _) = rhs {
                return lhsIndex == rhsIndex && lhsPinned == rhsPinned && lhsRow == rhsRow && lhsEditing == rhsEditing && lhsRevealed == rhsRevealed && lhsSelected == rhsSelected
            }
            return false
        }
    }

    static func <(lhs: ArbigramAccountsEntry, rhs: ArbigramAccountsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ArbigramAccountsArguments
        switch self {
        case let .pinnedHeader(text), let .otherHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .account(_, pinned, row, editing, revealed, selected, accountContext):
            // Each row's avatar belongs to a different account, so the item is
            // handed that account's engine rather than the current one.
            let itemContext = ItemListPeerItem.Context.custom(ItemListPeerItem.Context.Custom(
                accountPeerId: accountContext.account.peerId,
                engine: accountContext.engine,
                animationCache: arguments.context.animationCache,
                animationRenderer: arguments.context.animationRenderer,
                isPremiumDisabled: false,
                resolveInlineStickers: { fileIds in
                    return arguments.context.engine.stickers.resolveInlineStickers(fileIds: fileIds)
                }
            ))

            let subtitle = row.meta.tags.map({ "#" + $0 }).joined(separator: " ")

            // The colour rides the badge: customAvatarIcon replaces the avatar
            // outright, which trades a photo for a dot — a bad deal.
            var accountColor: UIColor?
            if row.meta.colorIndex >= 0 && row.meta.colorIndex < ArbigramAccountMeta.palette.count {
                accountColor = UIColor(rgb: ArbigramAccountMeta.palette[row.meta.colorIndex])
            }
            let label: ItemListPeerItemLabel
            if let accountColor {
                label = .attributedText(arbigramAccountMarker(color: accountColor, count: row.unreadCount > 0 ? "\(row.unreadCount)" : nil, theme: presentationData.theme))
            } else if row.unreadCount > 0 {
                label = .badge("\(row.unreadCount)")
            } else {
                label = .none
            }

            let pinTitle = presentationData.strings.baseLanguageCode.hasPrefix("ru")
                ? (pinned ? "Открепить" : "Закрепить")
                : (pinned ? "Unpin" : "Pin")

            return ItemListPeerItem(
                presentationData: presentationData,
                systemStyle: .glass,
                dateTimeFormat: presentationData.dateTimeFormat,
                nameDisplayOrder: .firstLast,
                context: itemContext,
                peer: row.peer,
                presence: nil,
                text: subtitle.isEmpty ? .none : .text(subtitle, .secondary),
                label: label,
                editing: ItemListPeerItemEditing(editable: true, editing: editing, canBeReordered: true, revealed: revealed),
                revealOptions: ItemListPeerItemRevealOptions(options: [
                    ItemListPeerItemRevealOption(type: .neutral, title: pinTitle, action: {
                        arguments.togglePinned(row.userId)
                    })
                ]),
                switchValue: selected.flatMap { ItemListPeerItemSwitch(value: $0, style: .check) },
                enabled: true,
                selectable: true,
                sectionId: self.section,
                action: {
                    if selected != nil {
                        arguments.toggleSelected(row.userId)
                    } else {
                        arguments.openAccount(row.userId)
                    }
                },
                setPeerIdWithRevealedOptions: { peerId, _ in
                    arguments.setRevealed(peerId)
                },
                removePeer: { _ in
                }
            )
        }
    }
}

private struct ArbigramAccountsState: Equatable {
    var editing: Bool = false
    var revealedPeerId: EnginePeer.Id?
    var reorderedIds: [Int64]?
    var metaRevision: Int = 0
    var selecting: Bool = false
    var selectedIds: Set<Int64> = []
    /// The record id is what logging out takes, and it is not derivable from
    /// the user id without going back to the account manager.
    var selectedRecordIds: [Int64: AccountRecordId] = [:]
}

public func arbigramAccountsController(context: AccountContext) -> ViewController {
    let statePromise = ValuePromise(ArbigramAccountsState(), ignoreRepeated: true)
    let stateValue = Atomic(value: ArbigramAccountsState())
    let updateState: ((inout ArbigramAccountsState) -> Void) -> Void = { f in
        statePromise.set(stateValue.modify { current in
            var updated = current
            f(&updated)
            return updated
        })
    }

    var pushControllerImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?
    var presentGroupActionsImpl: ((Set<Int64>) -> Void)?
    let actionsDisposable = DisposableSet()

    let arguments = ArbigramAccountsArguments(context: context, openAccount: { userId in
        pushControllerImpl?(arbigramAccountDetailController(context: context, userId: userId))
    }, togglePinned: { userId in
        var meta = ArbigramSettings.shared.meta(for: userId)
        meta.pinned = !meta.pinned
        ArbigramSettings.shared.setMeta(meta, for: userId)
        updateState { state in
            state.revealedPeerId = nil
            state.metaRevision += 1
        }
    }, setRevealed: { peerId in
        updateState { $0.revealedPeerId = peerId }
    }, toggleSelected: { userId in
        updateState { state in
            if state.selectedIds.contains(userId) {
                state.selectedIds.remove(userId)
            } else {
                state.selectedIds.insert(userId)
            }
        }
    })

    let signal = combineLatest(
        context.sharedContext.presentationData,
        activeAccountsAndPeers(context: context, includePrimary: true),
        statePromise.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, accountsAndPeers, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        let storedMeta = ArbigramSettings.shared.accountMeta

        var recordIds: [Int64: AccountRecordId] = [:]
        var rows: [(row: ArbigramAccountRow, context: AccountContext)] = []
        for (accountContext, peer, unreadCount) in accountsAndPeers.1 {
            let userId = accountContext.account.peerId.id._internalGetInt64Value()
            recordIds[userId] = accountContext.account.id
            rows.append((ArbigramAccountRow(
                recordId: accountContext.account.id,
                userId: userId,
                peer: peer,
                meta: storedMeta[userId] ?? ArbigramAccountMeta.empty,
                unreadCount: unreadCount
            ), accountContext))
        }

        // A drag that has not been written yet still has to show where it landed.
        if let reorderedIds = state.reorderedIds {
            var byId: [Int64: (row: ArbigramAccountRow, context: AccountContext)] = [:]
            for entry in rows {
                byId[entry.row.userId] = entry
            }
            var reordered: [(row: ArbigramAccountRow, context: AccountContext)] = []
            for id in reorderedIds {
                if let entry = byId.removeValue(forKey: id) {
                    reordered.append(entry)
                }
            }
            reordered.append(contentsOf: rows.filter { byId[$0.row.userId] != nil })
            rows = reordered
        }

        // Kept on the state so the action sheet, which runs later and
        // elsewhere, can turn a selection into something logout can take.
        if stateValue.with({ $0.selectedRecordIds }) != recordIds {
            Queue.mainQueue().async {
                updateState { $0.selectedRecordIds = recordIds }
            }
        }

        let pinned = rows.filter { $0.row.meta.pinned }
        let others = rows.filter { !$0.row.meta.pinned }

        var entries: [ArbigramAccountsEntry] = []
        var index = 0
        if !pinned.isEmpty {
            entries.append(.pinnedHeader(isRussian ? "ЗАКРЕПЛЁННЫЕ" : "PINNED"))
            for entry in pinned {
                entries.append(.account(index: index, pinned: true, row: entry.row, editing: state.editing, revealed: state.revealedPeerId == entry.row.peer.id, selected: state.selecting ? state.selectedIds.contains(entry.row.userId) : nil, context: entry.context))
                index += 1
            }
            entries.append(.otherHeader(isRussian ? "ОСТАЛЬНЫЕ" : "OTHER"))
        }
        for entry in others {
            entries.append(.account(index: index, pinned: false, row: entry.row, editing: state.editing, revealed: state.revealedPeerId == entry.row.peer.id, selected: state.selecting ? state.selectedIds.contains(entry.row.userId) : nil, context: entry.context))
            index += 1
        }
        entries.append(.info(isRussian
            ? "Потяни за строку, чтобы поменять порядок — он станет общим для всего приложения. Смахни влево, чтобы закрепить. Нажми на аккаунт, чтобы задать цвет и теги."
            : "Drag a row to change the order — it becomes the app's own. Swipe left to pin. Tap an account to give it a colour and tags."))

        let rightNavigationButton: ItemListNavigationButton
        let leftNavigationButton: ItemListNavigationButton
        if state.selecting {
            rightNavigationButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Done), style: .bold, enabled: true, action: {
                updateState { state in
                    state.selecting = false
                    state.selectedIds = []
                }
            })
            leftNavigationButton = ItemListNavigationButton(content: .text(isRussian ? "Действия" : "Actions"), style: .regular, enabled: !state.selectedIds.isEmpty, action: {
                presentGroupActionsImpl?(stateValue.with { $0.selectedIds })
            })
        } else {
            rightNavigationButton = ItemListNavigationButton(content: .text(state.editing ? presentationData.strings.Common_Done : presentationData.strings.Common_Edit), style: state.editing ? .bold : .regular, enabled: true, action: {
                updateState { state in
                    state.editing = !state.editing
                    state.revealedPeerId = nil
                }
            })
            leftNavigationButton = ItemListNavigationButton(content: .text(isRussian ? "Выбрать" : "Select"), style: .regular, enabled: rows.count > 1, action: {
                updateState { state in
                    state.selecting = true
                    state.editing = false
                    state.revealedPeerId = nil
                }
            })
        }

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(isRussian ? "Аккаунты" : "Accounts"),
            leftNavigationButton: leftNavigationButton,
            rightNavigationButton: rightNavigationButton,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks
        )
        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
        actionsDisposable.dispose()
    }

    let controller = ItemListController(context: context, state: signal)
    controller.didAppear = { _ in
        updateState { $0.metaRevision += 1 }
    }
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    presentGroupActionsImpl = { selectedIds in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        let count = selectedIds.count

        // Every action here writes the same store one account at a time; there
        // is no bulk write to get wrong, only a loop.
        func applyToSelection(_ transform: (inout ArbigramAccountMeta) -> Void) {
            for id in selectedIds {
                var meta = ArbigramSettings.shared.meta(for: id)
                transform(&meta)
                ArbigramSettings.shared.setMeta(meta, for: id)
            }
            updateState { state in
                state.metaRevision += 1
                state.selecting = false
                state.selectedIds = []
            }
        }

        func applyMuted(_ muted: Bool) {
            for id in selectedIds {
                ArbigramSettings.shared.setAccount(id, muted: muted)
            }
            updateState { state in
                state.selecting = false
                state.selectedIds = []
            }
        }

        var dismissActionSheetImpl: (() -> Void)?
        var items: [ActionSheetItem] = []
        items.append(ActionSheetTextItem(title: isRussian ? "Выбрано аккаунтов: \(count)" : "\(count) accounts selected"))
        items.append(ActionSheetButtonItem(title: isRussian ? "Включить уведомления" : "Turn notifications on", action: {
            dismissActionSheetImpl?()
            applyMuted(false)
        }))
        items.append(ActionSheetButtonItem(title: isRussian ? "Выключить уведомления" : "Turn notifications off", action: {
            dismissActionSheetImpl?()
            applyMuted(true)
        }))
        items.append(ActionSheetButtonItem(title: isRussian ? "Закрепить" : "Pin", action: {
            dismissActionSheetImpl?()
            applyToSelection { $0.pinned = true }
        }))
        items.append(ActionSheetButtonItem(title: isRussian ? "Открепить" : "Unpin", action: {
            dismissActionSheetImpl?()
            applyToSelection { $0.pinned = false }
        }))
        // Only tags that already exist, so a bulk action never needs a keyboard.
        for (index, tag) in ArbigramSettings.shared.knownTags.enumerated() where index < 8 {
            items.append(ActionSheetButtonItem(title: (isRussian ? "Повесить тег #" : "Add tag #") + tag, action: {
                dismissActionSheetImpl?()
                applyToSelection { meta in
                    if !meta.tags.contains(where: { $0.lowercased() == tag.lowercased() }) {
                        meta.tags.append(tag)
                    }
                }
            }))
        }
        items.append(ActionSheetButtonItem(title: isRussian ? "Снять все теги" : "Clear tags", action: {
            dismissActionSheetImpl?()
            applyToSelection { $0.tags = [] }
        }))
        if !ArbigramSettings.shared.secretPhrase.isEmpty {
            items.append(ActionSheetButtonItem(title: isRussian ? "Скрыть" : "Hide", action: {
                dismissActionSheetImpl?()
                applyToSelection { $0.hidden = true }
            }))
            items.append(ActionSheetButtonItem(title: isRussian ? "Показать" : "Unhide", action: {
                dismissActionSheetImpl?()
                applyToSelection { $0.hidden = false }
            }))
        }

        // Logging out sits apart from the rest and asks twice: once to be
        // sure, once for the phrase. Everything above it can be undone by
        // doing the opposite; this cannot be undone from inside the app at all.
        items.append(ActionSheetButtonItem(title: isRussian ? "Выйти из аккаунтов" : "Log Out", color: .destructive, action: {
            dismissActionSheetImpl?()
            let recordIds = stateValue.with { state -> [AccountRecordId] in
                return state.selectedRecordIds.filter { selectedIds.contains($0.key) }.map { $0.value }
            }
            if recordIds.isEmpty {
                return
            }
            let confirmation = textAlertController(
                context: context,
                title: isRussian ? "Выйти из аккаунтов" : "Log Out",
                text: isRussian
                    ? "Выход необратим: чтобы вернуться, понадобится номер и код. Аккаунтов: \(recordIds.count)."
                    : "Logging out cannot be undone — getting back in needs the phone and a code. Accounts: \(recordIds.count).",
                actions: [
                    TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                    TextAlertAction(type: .destructiveAction, title: isRussian ? "Выйти" : "Log Out", action: {
                        arbigramRequireSecretPhrase(context: context, present: { controller in
                            presentControllerImpl?(controller)
                        }, proceed: {
                            for recordId in recordIds {
                                let _ = logoutFromAccount(id: recordId, accountManager: context.sharedContext.accountManager, alreadyLoggedOutRemotely: false).startStandalone()
                            }
                            updateState { state in
                                state.selecting = false
                                state.selectedIds = []
                            }
                        })
                    })
                ]
            )
            presentControllerImpl?(confirmation)
        }))

        let actionSheet = ActionSheetController(presentationData: presentationData)
        dismissActionSheetImpl = { [weak actionSheet] in
            actionSheet?.dismissAnimated()
        }
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })
            ])
        ])
        presentControllerImpl?(actionSheet)
    }

    controller.setReorderEntry({ (fromIndex: Int, toIndex: Int, entries: [ArbigramAccountsEntry]) -> Signal<Bool, NoError> in
        var ordered: [(id: Int64, recordId: AccountRecordId)] = []
        for entry in entries {
            if case let .account(_, _, row, _, _, _, _) = entry {
                ordered.append((row.userId, row.recordId))
            }
        }
        guard fromIndex >= 0, fromIndex < ordered.count, toIndex >= 0, toIndex < ordered.count else {
            return .single(false)
        }
        let moved = ordered.remove(at: fromIndex)
        ordered.insert(moved, at: toIndex)

        updateState { $0.reorderedIds = ordered.map { $0.id } }
        actionsDisposable.add(applyArbigramAccountOrder(context: context, orderedIds: ordered.map { $0.recordId }).start())
        return .single(true)
    })

    return controller
}

// MARK: - One account

private enum ArbigramAccountDetailSection: Int32 {
    case pinned
    case clearChats
    case keepDeleted
    case hidden
    case color
    case tags
}

private final class ArbigramAccountDetailArguments {
    let setPinned: (Bool) -> Void
    let setKeepDeleted: (Bool) -> Void
    let setHidden: (Bool) -> Void
    let setColor: (Int) -> Void
    let setTags: (String) -> Void
    let clearPrivateChats: () -> Void

    init(setPinned: @escaping (Bool) -> Void, setKeepDeleted: @escaping (Bool) -> Void, setHidden: @escaping (Bool) -> Void, setColor: @escaping (Int) -> Void, clearPrivateChats: @escaping () -> Void, setTags: @escaping (String) -> Void) {
        self.setPinned = setPinned
        self.setKeepDeleted = setKeepDeleted
        self.setHidden = setHidden
        self.setColor = setColor
        self.setTags = setTags
        self.clearPrivateChats = clearPrivateChats
    }
}

private enum ArbigramAccountDetailEntry: ItemListNodeEntry {
    case pinned(String, Bool)
    case keepDeleted(String, Bool)
    case keepDeletedInfo(String)
    case hidden(String, Bool)
    case hiddenInfo(String)
    case colorHeader(String)
    case color(Int, String, Bool)
    case tagsHeader(String)
    case tags(String, String)
    case tagsInfo(String)
    case clearChats(String)
    case clearChatsInfo(String)

    var section: ItemListSectionId {
        switch self {
        case .pinned:
            return ArbigramAccountDetailSection.pinned.rawValue
        case .keepDeleted, .keepDeletedInfo:
            return ArbigramAccountDetailSection.keepDeleted.rawValue
        case .hidden, .hiddenInfo:
            return ArbigramAccountDetailSection.hidden.rawValue
        case .colorHeader, .color:
            return ArbigramAccountDetailSection.color.rawValue
        case .tagsHeader, .tags, .tagsInfo:
            return ArbigramAccountDetailSection.tags.rawValue
        case .clearChats, .clearChatsInfo:
            return ArbigramAccountDetailSection.clearChats.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .pinned:
            return 0
        case .keepDeleted:
            return 1
        case .keepDeletedInfo:
            return 2
        case .hidden:
            return 3
        case .hiddenInfo:
            return 4
        case .colorHeader:
            return 5
        case let .color(index, _, _):
            return Int32(10 + index)
        case .tagsHeader:
            return 100
        case .tags:
            return 101
        case .tagsInfo:
            return 102
        case .clearChats:
            return 200
        case .clearChatsInfo:
            return 201
        }
    }

    static func <(lhs: ArbigramAccountDetailEntry, rhs: ArbigramAccountDetailEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ArbigramAccountDetailArguments
        switch self {
        case let .pinned(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setPinned(value)
            })
        case let .keepDeleted(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, maximumNumberOfLines: 2, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setKeepDeleted(value)
            })
        case let .keepDeletedInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .hidden(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, maximumNumberOfLines: 2, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setHidden(value)
            })
        case let .hiddenInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .colorHeader(text), let .tagsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .color(index, title, selected):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .right, checked: selected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.setColor(index)
            })
        case let .tags(placeholder, value):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: ""), text: value, placeholder: placeholder, type: .regular(capitalization: false, autocorrection: false), clearType: .always, sectionId: self.section, textUpdated: { value in
                arguments.setTags(value)
            }, action: {})
        case let .tagsInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .clearChats(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.clearPrivateChats()
            })
        case let .clearChatsInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private struct ArbigramAccountDetailState: Equatable {
    var meta: ArbigramAccountMeta
    var tagsText: String
    var keepDeleted: Bool
}

public func arbigramAccountDetailController(context: AccountContext, userId: Int64) -> ViewController {
    let initialMeta = ArbigramSettings.shared.meta(for: userId)
    let statePromise = ValuePromise(ArbigramAccountDetailState(meta: initialMeta, tagsText: initialMeta.tags.joined(separator: ", "), keepDeleted: ArbigramSettings.shared.keepsDeletedMessages(accountId: userId)), ignoreRepeated: true)
    let stateValue = Atomic(value: ArbigramAccountDetailState(meta: initialMeta, tagsText: initialMeta.tags.joined(separator: ", "), keepDeleted: ArbigramSettings.shared.keepsDeletedMessages(accountId: userId)))
    let updateState: ((inout ArbigramAccountDetailState) -> Void) -> Void = { f in
        statePromise.set(stateValue.modify { current in
            var updated = current
            f(&updated)
            ArbigramSettings.shared.setMeta(updated.meta, for: userId)
            return updated
        })
    }

    var presentImpl: ((ViewController) -> Void)?

    let arguments = ArbigramAccountDetailArguments(setPinned: { value in
        updateState { $0.meta.pinned = value }
    }, setKeepDeleted: { value in
        ArbigramSettings.shared.setKeepsDeletedMessages(value, accountId: userId)
        updateState { $0.keepDeleted = value }
    }, setHidden: { value in
        updateState { $0.meta.hidden = value }
    }, setColor: { index in
        updateState { state in
            // Tapping the current colour clears it, so there is no separate
            // "none" row to explain.
            state.meta.colorIndex = state.meta.colorIndex == index ? -1 : index
        }
    }, clearPrivateChats: {
        // Counted before it is described: "all your chats" is not a number, and
        // the number is the part worth reading twice.
        let _ = (arbigramAccountContext(context: context, userId: userId)
        |> mapToSignal { accountContext -> Signal<(AccountContext, [EnginePeer])?, NoError> in
            guard let accountContext else {
                return .single(nil)
            }
            return arbigramPrivateChatPeers(context: accountContext)
            |> map { peers -> (AccountContext, [EnginePeer])? in
                return (accountContext, peers)
            }
        }
        |> deliverOnMainQueue).startStandalone(next: { result in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")

            guard let (accountContext, peers) = result, !peers.isEmpty else {
                presentImpl?(textAlertController(context: context, title: nil, text: isRussian ? "Личных чатов нет." : "There are no private chats.", actions: [
                    TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
                ]))
                return
            }

            presentImpl?(textAlertController(
                context: context,
                title: isRussian ? "Очистить личные чаты" : "Clear Private Chats",
                text: isRussian
                    ? "Переписка будет удалена у обеих сторон в \(peers.count) чатах — и твои сообщения, и собеседника. У него чат станет пустым. Это необратимо.\n\nГруппы, каналы и боты не затрагиваются: там чужие сообщения удалить нельзя."
                    : "History will be deleted for both sides in \(peers.count) chats — your messages and theirs. Their chat becomes empty. This cannot be undone.\n\nGroups, channels and bots are untouched: nobody else's messages can be removed there.",
                actions: [
                    TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                    TextAlertAction(type: .destructiveAction, title: isRussian ? "Очистить" : "Clear", action: {
                        arbigramRequireSecretPhrase(context: context, present: { controller in
                            presentImpl?(controller)
                        }, proceed: {
                            let _ = (arbigramClearPrivateChats(context: accountContext, peers: peers)
                            |> deliverOnMainQueue).startStandalone(completed: {
                                presentImpl?(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: isRussian ? "Готово: \(peers.count)" : "Done: \(peers.count)", timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }))
                            })
                        })
                    })
                ]
            ))
        })
    }, setTags: { text in
        updateState { state in
            state.tagsText = text
            state.meta.tags = text.components(separatedBy: CharacterSet(charactersIn: ",#"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    })

    let colorNamesRu = ["Красный", "Оранжевый", "Жёлтый", "Зелёный", "Бирюзовый", "Синий", "Фиолетовый", "Розовый"]
    let colorNamesEn = ["Red", "Orange", "Yellow", "Green", "Teal", "Blue", "Violet", "Pink"]

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        var entries: [ArbigramAccountDetailEntry] = []
        entries.append(.pinned(isRussian ? "Закрепить наверху" : "Pin to the top", state.meta.pinned))
        if ArbigramSettings.shared.keepDeletedMessages {
            entries.append(.keepDeleted(isRussian ? "Сохранять удалённые здесь" : "Keep Deleted Messages Here", state.keepDeleted))
            entries.append(.keepDeletedInfo(isRussian
                ? "Общий переключатель включён. Здесь можно выключить запись именно для этого аккаунта."
                : "The master switch is on. This turns the log off for this account alone."))
        }
        if !ArbigramSettings.shared.secretPhrase.isEmpty {
            entries.append(.hidden(isRussian ? "Скрыть аккаунт" : "Hide this account", state.meta.hidden))
            entries.append(.hiddenInfo(isRussian
                ? "Аккаунт пропадёт из всех списков. Вернуть — ввести свою фразу в поиск чатов; при следующем запуске он снова скроется."
                : "The account disappears from every list. Type your phrase into chat search to bring it back; the next launch hides it again."))
        }
        entries.append(.colorHeader(isRussian ? "ЦВЕТ" : "COLOUR"))
        for index in 0 ..< ArbigramAccountMeta.palette.count {
            let name = isRussian ? colorNamesRu[index] : colorNamesEn[index]
            entries.append(.color(index, name, state.meta.colorIndex == index))
        }
        entries.append(.tagsHeader(isRussian ? "ТЕГИ" : "TAGS"))
        entries.append(.tags(isRussian ? "байер, гео RU, прогрев" : "buyer, geo RU, warmup", state.tagsText))
        entries.append(.tagsInfo(isRussian
            ? "Через запятую. Видно под именем — и здесь, и в списке аккаунтов в настройках."
            : "Comma separated. Shown under the name here and in the settings account list."))
        entries.append(.clearChats(isRussian ? "Очистить все личные чаты" : "Clear All Private Chats"))
        entries.append(.clearChatsInfo(isRussian
            ? "Удаляет переписку у обеих сторон во всех личных чатах этого аккаунта. Группы, каналы и боты не затрагиваются. Спросит подтверждение и фразу."
            : "Deletes the history for both sides in every private chat on this account. Groups, channels and bots are untouched. Asks for confirmation and the phrase."))

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(isRussian ? "Аккаунт" : "Account"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}
