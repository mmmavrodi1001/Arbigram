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
import ArbigramSettings

private let arbigramAccountsSectionPinned: ItemListSectionId = 0
private let arbigramAccountsSectionOther: ItemListSectionId = 1

/// Telegram already stores an order per account record — the iOS app just never
/// offered a way to change it. Writing it here means the new order is the real
/// one, and every list that shows accounts follows.
private func applyArbigramAccountOrder(context: AccountContext, orderedIds: [AccountRecordId]) -> Signal<Never, NoError> {
    return context.sharedContext.accountManager.transaction { transaction -> Void in
        for (index, id) in orderedIds.enumerated() {
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

    init(context: AccountContext, openAccount: @escaping (Int64) -> Void, togglePinned: @escaping (Int64) -> Void, setRevealed: @escaping (EnginePeer.Id?) -> Void) {
        self.context = context
        self.openAccount = openAccount
        self.togglePinned = togglePinned
        self.setRevealed = setRevealed
    }
}

private enum ArbigramAccountsEntry: ItemListNodeEntry {
    case pinnedHeader(String)
    case otherHeader(String)
    case account(index: Int, pinned: Bool, row: ArbigramAccountRow, editing: Bool, revealed: Bool, context: AccountContext)
    case info(String)

    var section: ItemListSectionId {
        switch self {
        case .pinnedHeader:
            return arbigramAccountsSectionPinned
        case let .account(_, pinned, _, _, _, _):
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
        case let .account(index, _, _, _, _, _):
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
        case let .account(lhsIndex, lhsPinned, lhsRow, lhsEditing, lhsRevealed, _):
            if case let .account(rhsIndex, rhsPinned, rhsRow, rhsEditing, rhsRevealed, _) = rhs {
                return lhsIndex == rhsIndex && lhsPinned == rhsPinned && lhsRow == rhsRow && lhsEditing == rhsEditing && lhsRevealed == rhsRevealed
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
        case let .account(_, pinned, row, editing, revealed, accountContext):
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

            var subtitle = row.meta.tags.map({ "#" + $0 }).joined(separator: " ")
            if !row.meta.note.isEmpty {
                subtitle = subtitle.isEmpty ? row.meta.note : subtitle + " · " + row.meta.note
            }

            var customAvatarIcon: UIImage?
            if row.meta.colorIndex >= 0 && row.meta.colorIndex < ArbigramAccountMeta.palette.count {
                customAvatarIcon = arbigramColorDot(UIColor(rgb: ArbigramAccountMeta.palette[row.meta.colorIndex]))
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
                customAvatarIcon: customAvatarIcon,
                presence: nil,
                text: subtitle.isEmpty ? .none : .text(subtitle, .secondary),
                label: row.unreadCount > 0 ? .badge("\(row.unreadCount)", presentationData.theme.list.itemAccentColor) : .none,
                editing: ItemListPeerItemEditing(editable: true, editing: editing, canBeReordered: true, revealed: revealed),
                revealOptions: ItemListPeerItemRevealOptions(options: [
                    ItemListPeerItemRevealOption(type: .neutral, title: pinTitle, action: {
                        arguments.togglePinned(row.userId)
                    })
                ]),
                switchValue: nil,
                enabled: true,
                selectable: true,
                sectionId: self.section,
                action: {
                    arguments.openAccount(row.userId)
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

/// A filled circle the size of the avatar badge, used to tell accounts apart at
/// a glance without an extra row of chrome.
private func arbigramColorDot(_ color: UIColor) -> UIImage? {
    let size = CGSize(width: 12.0, height: 12.0)
    UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
    defer {
        UIGraphicsEndImageContext()
    }
    guard let context = UIGraphicsGetCurrentContext() else {
        return nil
    }
    context.setFillColor(color.cgColor)
    context.fillEllipse(in: CGRect(origin: CGPoint(), size: size))
    return UIGraphicsGetImageFromCurrentImageContext()
}

private struct ArbigramAccountsState: Equatable {
    var editing: Bool = false
    var revealedPeerId: EnginePeer.Id?
    var reorderedIds: [Int64]?
    var metaRevision: Int = 0
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

        var rows: [(row: ArbigramAccountRow, context: AccountContext)] = []
        for (accountContext, peer, unreadCount) in accountsAndPeers.1 {
            let userId = accountContext.account.peerId.id._internalGetInt64Value()
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

        let pinned = rows.filter { $0.row.meta.pinned }
        let others = rows.filter { !$0.row.meta.pinned }

        var entries: [ArbigramAccountsEntry] = []
        var index = 0
        if !pinned.isEmpty {
            entries.append(.pinnedHeader(isRussian ? "ЗАКРЕПЛЁННЫЕ" : "PINNED"))
            for entry in pinned {
                entries.append(.account(index: index, pinned: true, row: entry.row, editing: state.editing, revealed: state.revealedPeerId == entry.row.peer.id, context: entry.context))
                index += 1
            }
            entries.append(.otherHeader(isRussian ? "ОСТАЛЬНЫЕ" : "OTHER"))
        }
        for entry in others {
            entries.append(.account(index: index, pinned: false, row: entry.row, editing: state.editing, revealed: state.revealedPeerId == entry.row.peer.id, context: entry.context))
            index += 1
        }
        entries.append(.info(isRussian
            ? "Потяни за строку, чтобы поменять порядок — он станет общим для всего приложения. Смахни влево, чтобы закрепить. Нажми на аккаунт, чтобы задать цвет, теги и заметку."
            : "Drag a row to change the order — it becomes the app's own. Swipe left to pin. Tap an account to give it a colour, tags and a note."))

        let rightNavigationButton = ItemListNavigationButton(content: .text(state.editing ? presentationData.strings.Common_Done : presentationData.strings.Common_Edit), style: state.editing ? .bold : .regular, enabled: true, action: {
            updateState { state in
                state.editing = !state.editing
                state.revealedPeerId = nil
            }
        })

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(isRussian ? "Аккаунты" : "Accounts"),
            leftNavigationButton: nil,
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

    controller.setReorderEntry({ (fromIndex: Int, toIndex: Int, entries: [ArbigramAccountsEntry]) -> Signal<Bool, NoError> in
        var ordered: [(id: Int64, recordId: AccountRecordId)] = []
        for entry in entries {
            if case let .account(_, _, row, _, _, _) = entry {
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
    case color
    case tags
    case note
}

private final class ArbigramAccountDetailArguments {
    let setPinned: (Bool) -> Void
    let setColor: (Int) -> Void
    let setTags: (String) -> Void
    let setNote: (String) -> Void

    init(setPinned: @escaping (Bool) -> Void, setColor: @escaping (Int) -> Void, setTags: @escaping (String) -> Void, setNote: @escaping (String) -> Void) {
        self.setPinned = setPinned
        self.setColor = setColor
        self.setTags = setTags
        self.setNote = setNote
    }
}

private enum ArbigramAccountDetailEntry: ItemListNodeEntry {
    case pinned(String, Bool)
    case colorHeader(String)
    case color(Int, String, Bool)
    case tagsHeader(String)
    case tags(String, String)
    case tagsInfo(String)
    case noteHeader(String)
    case note(String, String)

    var section: ItemListSectionId {
        switch self {
        case .pinned:
            return ArbigramAccountDetailSection.pinned.rawValue
        case .colorHeader, .color:
            return ArbigramAccountDetailSection.color.rawValue
        case .tagsHeader, .tags, .tagsInfo:
            return ArbigramAccountDetailSection.tags.rawValue
        case .noteHeader, .note:
            return ArbigramAccountDetailSection.note.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .pinned:
            return 0
        case .colorHeader:
            return 1
        case let .color(index, _, _):
            return Int32(10 + index)
        case .tagsHeader:
            return 100
        case .tags:
            return 101
        case .tagsInfo:
            return 102
        case .noteHeader:
            return 200
        case .note:
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
        case let .colorHeader(text), let .tagsHeader(text), let .noteHeader(text):
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
        case let .note(placeholder, value):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: ""), text: value, placeholder: placeholder, sectionId: self.section, textUpdated: { value in
                arguments.setNote(value)
            }, action: {})
        }
    }
}

private struct ArbigramAccountDetailState: Equatable {
    var meta: ArbigramAccountMeta
    var tagsText: String
}

public func arbigramAccountDetailController(context: AccountContext, userId: Int64) -> ViewController {
    let initialMeta = ArbigramSettings.shared.meta(for: userId)
    let statePromise = ValuePromise(ArbigramAccountDetailState(meta: initialMeta, tagsText: initialMeta.tags.joined(separator: ", ")), ignoreRepeated: true)
    let stateValue = Atomic(value: ArbigramAccountDetailState(meta: initialMeta, tagsText: initialMeta.tags.joined(separator: ", ")))
    let updateState: ((inout ArbigramAccountDetailState) -> Void) -> Void = { f in
        statePromise.set(stateValue.modify { current in
            var updated = current
            f(&updated)
            ArbigramSettings.shared.setMeta(updated.meta, for: userId)
            return updated
        })
    }

    let arguments = ArbigramAccountDetailArguments(setPinned: { value in
        updateState { $0.meta.pinned = value }
    }, setColor: { index in
        updateState { state in
            // Tapping the current colour clears it, so there is no separate
            // "none" row to explain.
            state.meta.colorIndex = state.meta.colorIndex == index ? -1 : index
        }
    }, setTags: { text in
        updateState { state in
            state.tagsText = text
            state.meta.tags = text.components(separatedBy: CharacterSet(charactersIn: ",#"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    }, setNote: { text in
        updateState { $0.meta.note = text }
    })

    let colorNamesRu = ["Красный", "Оранжевый", "Жёлтый", "Зелёный", "Бирюзовый", "Синий", "Фиолетовый", "Розовый"]
    let colorNamesEn = ["Red", "Orange", "Yellow", "Green", "Teal", "Blue", "Violet", "Pink"]

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        var entries: [ArbigramAccountDetailEntry] = []
        entries.append(.pinned(isRussian ? "Закрепить наверху" : "Pin to the top", state.meta.pinned))
        entries.append(.colorHeader(isRussian ? "ЦВЕТ" : "COLOUR"))
        for index in 0 ..< ArbigramAccountMeta.palette.count {
            let name = isRussian ? colorNamesRu[index] : colorNamesEn[index]
            entries.append(.color(index, name, state.meta.colorIndex == index))
        }
        entries.append(.tagsHeader(isRussian ? "ТЕГИ" : "TAGS"))
        entries.append(.tags(isRussian ? "байер, гео RU, прогрев" : "buyer, geo RU, warmup", state.tagsText))
        entries.append(.tagsInfo(isRussian
            ? "Через запятую. Теги видно в списке аккаунтов под именем."
            : "Comma separated. Tags show under the name in the account list."))
        entries.append(.noteHeader(isRussian ? "ЗАМЕТКА" : "NOTE"))
        entries.append(.note(isRussian ? "Для чего этот аккаунт" : "What this account is for", state.meta.note))

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

    return ItemListController(context: context, state: signal)
}
