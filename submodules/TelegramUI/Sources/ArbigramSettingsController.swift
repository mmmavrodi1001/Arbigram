import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import TelegramCore
import ArbigramSettings
import AccountUtils

/// Two languages, picked from the app's own. New keys cannot go into the
/// localisation files without regenerating the whole string table, and the fork
/// is read by exactly two audiences.
private func loc(_ strings: PresentationStrings, _ ru: String, _ en: String) -> String {
    return strings.baseLanguageCode.hasPrefix("ru") ? ru : en
}

private enum ArbigramSettingsSection: Int32 {
    case stories
    case sponsored
    case peerId
    case readReceipts
    case inputActivity
    case copyProtection
    case contactsTab
    case secretMedia
    case deletedMessages
    case deletedAlerts
    case plainNotifications
    case notificationAccounts
    case accounts
    case secretPhrase
}

private final class ArbigramSettingsArguments {
    let set: (ArbigramSwitch, Bool) -> Void
    let openNotificationAccounts: () -> Void
    let openAccounts: () -> Void
    let setSecretPhrase: (String) -> Void
    let openDeletedMessages: () -> Void

    init(set: @escaping (ArbigramSwitch, Bool) -> Void, openNotificationAccounts: @escaping () -> Void, openAccounts: @escaping () -> Void, setSecretPhrase: @escaping (String) -> Void, openDeletedMessages: @escaping () -> Void) {
        self.set = set
        self.openNotificationAccounts = openNotificationAccounts
        self.openAccounts = openAccounts
        self.setSecretPhrase = setSecretPhrase
        self.openDeletedMessages = openDeletedMessages
    }
}

private enum ArbigramSwitch: Int32, CaseIterable {
    case hideStories
    case hideSponsoredMessages
    case showPeerId
    case skipReadHistory
    case hideInputActivity
    case ignoreCopyProtection
    case hideContactsTab
    case saveSecretMedia
    case keepDeletedMessages
    case announceDeletedMessages
    case plainNotifications

    var section: ArbigramSettingsSection {
        switch self {
        case .hideStories: return .stories
        case .hideSponsoredMessages: return .sponsored
        case .showPeerId: return .peerId
        case .skipReadHistory: return .readReceipts
        case .hideInputActivity: return .inputActivity
        case .ignoreCopyProtection: return .copyProtection
        case .hideContactsTab: return .contactsTab
        case .saveSecretMedia: return .secretMedia
        case .keepDeletedMessages: return .deletedMessages
        case .announceDeletedMessages: return .deletedAlerts
        case .plainNotifications: return .plainNotifications
        }
    }

    func title(_ strings: PresentationStrings) -> String {
        switch self {
        case .hideStories:
            return loc(strings, "Скрыть Истории", "Hide Stories")
        case .hideSponsoredMessages:
            return loc(strings, "Убрать рекламу", "Hide Sponsored Messages")
        case .showPeerId:
            return loc(strings, "Показывать ID в профилях", "Show ID in Profiles")
        case .skipReadHistory:
            return loc(strings, "Не отправлять «прочитано»", "Don't Send Read Receipts")
        case .hideInputActivity:
            return loc(strings, "Скрыть «печатает…»", "Hide Typing Status")
        case .ignoreCopyProtection:
            return loc(strings, "Копировать и скачивать везде", "Ignore Copy Protection")
        case .hideContactsTab:
            return loc(strings, "Скрыть вкладку «Контакты»", "Hide the Contacts Tab")
        case .saveSecretMedia:
            return loc(strings, "Сохранять сгорающие медиа", "Save Self-Destructing Media")
        case .keepDeletedMessages:
            return loc(strings, "Сохранять удалённые сообщения", "Keep Deleted Messages")
        case .announceDeletedMessages:
            return loc(strings, "Уведомлять об удалённых", "Notify About Deletions")
        case .plainNotifications:
            return loc(strings, "Текст в уведомлениях", "Text in Notifications")
        }
    }

    func info(_ strings: PresentationStrings) -> String {
        switch self {
        case .hideStories:
            return loc(strings,
                       "Убирает ленту историй над списком чатов.",
                       "Removes the stories strip above the chat list.")
        case .hideSponsoredMessages:
            return loc(strings,
                       "Спонсорские сообщения не запрашиваются у сервера, а не прячутся после получения. Уже открытые чаты доживут со своим состоянием до переоткрытия.",
                       "Sponsored messages are never requested from the server rather than hidden on arrival. Chats already open keep their current state until reopened.")
        case .showPeerId:
            return loc(strings,
                       "Добавляет числовой идентификатор в профили людей, групп и каналов. Нажатие копирует.",
                       "Adds the numeric identifier to user, group and channel profiles. Tap it to copy.")
        case .skipReadHistory:
            return loc(strings,
                       "Собеседник не увидит, что сообщение прочитано. Распространяется и на реакции, и на истории. Учти: пока ты не отправляешь отметки, чужие отметки о прочтении тебе тоже приходят не всегда.",
                       "Nobody sees your messages marked as read — reactions and stories included. Note that while you withhold receipts, other people's are not always delivered to you either.")
        case .hideInputActivity:
            return loc(strings,
                       "Не отправлять «печатает…», «записывает голосовое» и «отправляет файл».",
                       "Stops sending typing, voice-recording and file-uploading indicators.")
        case .ignoreCopyProtection:
            return loc(strings,
                       "Выделение текста, копирование и сохранение медиа работают в чатах и каналах с запретом на пересылку.",
                       "Text selection, copying and saving media work in chats and channels that forbid forwarding.")
        case .hideContactsTab:
            return loc(strings,
                       "Убирает «Контакты» из нижней панели. Сами контакты остаются — их видно через поиск. Вкладка «Звонки» прячется своим переключателем в Настройках → Звонки.",
                       "Removes Contacts from the tab bar. The contacts themselves stay and remain reachable through search. The Calls tab has its own switch under Settings, Calls.")
        case .saveSecretMedia:
            return loc(strings,
                       "Фото и видео с таймером сохраняются в галерею в момент открытия. Отправитель по-прежнему увидит, что ты их посмотрел — это отдельная отметка, и она уходит так же, как раньше.",
                       "Photos and videos with a timer are copied to the camera roll as they open. The sender still sees that you viewed them — that is a separate receipt and it is sent as before.")
        case .keepDeletedMessages:
            return loc(strings,
                       "Когда собеседник удаляет присланное сообщение, его текст и вид вложения остаются в отдельном списке. Само сообщение из чата всё равно исчезает — трогать хранилище переписки ради этого слишком рискованно. Свои удалённые сообщения не записываются.",
                       "When the other side deletes a message they sent you, its text and attachment kind stay in a separate list. The message still leaves the chat — rewriting the message store for this is not worth the risk. Your own deletions are not recorded.")
        case .announceDeletedMessages:
            return loc(strings,
                       "Показывать уведомление в момент удаления, а не ждать, пока ты откроешь список. Пачка удалённых сообщений приходит одним уведомлением, а не полусотней.",
                       "Show a notification when the deletion happens instead of waiting until the list is opened. A batch arrives as one notification rather than fifty.")
        case .plainNotifications:
            return loc(strings,
                       "Вернуть текст в уведомления. Обычно его расшифровывает отдельный компонент, который наша подпись не покрывает — поэтому приходит «Новое сообщение». Тут телефон просит сервер присылать текст сразу, без шифрования: он становится виден тем, через кого проходит уведомление. Переподключение занимает пару минут.",
                       "Puts the text back into notifications. It is normally decrypted by a separate component this signing profile cannot cover, which is why they arrive blank. This asks the server to send the text in the clear instead, so it becomes readable to whoever handles the push. Re-registering takes a couple of minutes.")
        }
    }

    func value(_ settings: ArbigramSettingsState) -> Bool {
        switch self {
        case .hideStories: return settings.hideStories
        case .hideSponsoredMessages: return settings.hideSponsoredMessages
        case .showPeerId: return settings.showPeerId
        case .skipReadHistory: return settings.skipReadHistory
        case .hideInputActivity: return settings.hideInputActivity
        case .ignoreCopyProtection: return settings.ignoreCopyProtection
        case .hideContactsTab: return settings.hideContactsTab
        case .saveSecretMedia: return settings.saveSecretMedia
        case .keepDeletedMessages: return settings.keepDeletedMessages
        case .announceDeletedMessages: return settings.announceDeletedMessages
        case .plainNotifications: return settings.plainNotifications
        }
    }

    func write(_ value: Bool) {
        switch self {
        case .hideStories: ArbigramSettings.shared.hideStories = value
        case .hideSponsoredMessages: ArbigramSettings.shared.hideSponsoredMessages = value
        case .showPeerId: ArbigramSettings.shared.showPeerId = value
        case .skipReadHistory: ArbigramSettings.shared.skipReadHistory = value
        case .hideInputActivity: ArbigramSettings.shared.hideInputActivity = value
        case .ignoreCopyProtection: ArbigramSettings.shared.ignoreCopyProtection = value
        case .hideContactsTab: ArbigramSettings.shared.hideContactsTab = value
        case .saveSecretMedia: ArbigramSettings.shared.saveSecretMedia = value
        case .keepDeletedMessages: ArbigramSettings.shared.keepDeletedMessages = value
        case .announceDeletedMessages: ArbigramSettings.shared.announceDeletedMessages = value
        case .plainNotifications: ArbigramSettings.shared.plainNotifications = value
        }
    }
}

private enum ArbigramSettingsEntry: ItemListNodeEntry {
    case toggle(ArbigramSwitch, Bool)
    case info(ArbigramSwitch)
    case notificationAccounts(Int)
    case notificationAccountsInfo
    case accounts
    case deletedMessages(Int)
    case secretPhrase(String)
    case secretPhraseInfo

    var section: ItemListSectionId {
        switch self {
        case let .toggle(item, _):
            return item.section.rawValue
        case let .info(item):
            return item.section.rawValue
        case .notificationAccounts, .notificationAccountsInfo:
            return ArbigramSettingsSection.notificationAccounts.rawValue
        case .accounts:
            return ArbigramSettingsSection.accounts.rawValue
        case .deletedMessages:
            return ArbigramSettingsSection.deletedMessages.rawValue
        case .secretPhrase, .secretPhraseInfo:
            return ArbigramSettingsSection.secretPhrase.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case let .toggle(item, _):
            return item.rawValue * 2
        case let .info(item):
            return item.rawValue * 2 + 1
        case .notificationAccounts:
            return 100
        case .notificationAccountsInfo:
            return 101
        case .accounts:
            return 102
        case .deletedMessages:
            return 103
        case .secretPhrase:
            return 110
        case .secretPhraseInfo:
            return 111
        }
    }

    static func <(lhs: ArbigramSettingsEntry, rhs: ArbigramSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ArbigramSettingsArguments
        switch self {
        case let .toggle(item, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: item.title(presentationData.strings), value: value, maximumNumberOfLines: 2, sectionId: self.section, style: .blocks, updated: { value in
                arguments.set(item, value)
            })
        case let .info(item):
            return ItemListTextItem(presentationData: presentationData, text: .plain(item.info(presentationData.strings)), sectionId: self.section)
        case let .notificationAccounts(mutedCount):
            let label: String
            if mutedCount == 0 {
                label = loc(presentationData.strings, "Все", "All")
            } else {
                label = loc(presentationData.strings, "Выключено: \(mutedCount)", "\(mutedCount) off")
            }
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: loc(presentationData.strings, "Уведомления по аккаунтам", "Notifications by Account"), label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openNotificationAccounts()
            })
        case .notificationAccountsInfo:
            return ItemListTextItem(presentationData: presentationData, text: .plain(loc(presentationData.strings,
                "Выбери, с каких аккаунтов приходят уведомления. Выключенный аккаунт снимает свой токен с сервера — пуши по нему не отправляются вообще, а не прячутся на телефоне.",
                "Choose which accounts notify you. An account switched off withdraws its token from the server, so nothing is sent for it at all rather than hidden on arrival.")), sectionId: self.section)
        case .accounts:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: loc(presentationData.strings, "Аккаунты", "Accounts"), label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openAccounts()
            })
        case let .deletedMessages(count):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: loc(presentationData.strings, "Удалённые сообщения", "Deleted Messages"), label: count > 0 ? "\(count)" : "", sectionId: self.section, style: .blocks, action: {
                arguments.openDeletedMessages()
            })
        case let .secretPhrase(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: ""), text: value, placeholder: loc(presentationData.strings, "Фраза для скрытых аккаунтов", "Phrase for hidden accounts"), type: .regular(capitalization: false, autocorrection: false), clearType: .always, sectionId: self.section, textUpdated: { value in
                arguments.setSecretPhrase(value)
            }, action: {})
        case .secretPhraseInfo:
            return ItemListTextItem(presentationData: presentationData, text: .plain(loc(presentationData.strings,
                "Задай фразу, и в настройках аккаунта появится переключатель «Скрыть». Скрытый аккаунт исчезает отовсюду. Чтобы достать — введи фразу в поиск над списком чатов; поиск на неё не отреагирует, но скрытые вернутся до перезапуска.\n\nЭта строка сама пропадёт, как только хоть один аккаунт будет скрыт, и вернётся, когда ты их покажешь.",
                "Set a phrase and a Hide switch appears in each account's settings. A hidden account disappears everywhere. To bring it back, type the phrase into the search above the chat list; search will not react to it, but hidden accounts return until the next launch.\n\nThis row disappears once anything is hidden, and comes back when you reveal them.")), sectionId: self.section)
        }
    }
}

private struct ArbigramSettingsState: Equatable {
    var hideStories: Bool
    var hideSponsoredMessages: Bool
    var showPeerId: Bool
    var skipReadHistory: Bool
    var hideInputActivity: Bool
    var ignoreCopyProtection: Bool
    var hideContactsTab: Bool
    var saveSecretMedia: Bool
    var keepDeletedMessages: Bool
    var announceDeletedMessages: Bool
    var plainNotifications: Bool
    var deletedMessageCount: Int
    var mutedAccountCount: Int
    var secretPhrase: String
    var hasHiddenAccounts: Bool
    var hiddenRevealed: Bool

    init(accountId: Int64) {
        let settings = ArbigramSettings.shared
        self.hideStories = settings.hideStories
        self.hideSponsoredMessages = settings.hideSponsoredMessages
        self.showPeerId = settings.showPeerId
        self.skipReadHistory = settings.skipReadHistory
        self.hideInputActivity = settings.hideInputActivity
        self.ignoreCopyProtection = settings.ignoreCopyProtection
        self.hideContactsTab = settings.hideContactsTab
        self.saveSecretMedia = settings.saveSecretMedia
        self.keepDeletedMessages = settings.keepDeletedMessages
        self.announceDeletedMessages = settings.announceDeletedMessages
        self.plainNotifications = settings.plainNotifications
        self.deletedMessageCount = settings.deletedMessages(accountId: accountId).count
        self.mutedAccountCount = settings.mutedAccountIds.count
        self.secretPhrase = settings.secretPhrase
        self.hasHiddenAccounts = settings.hasHiddenAccounts
        self.hiddenRevealed = settings.hiddenRevealed
    }
}

/// The switches are not backed by a signal — the store has to be readable from
/// TelegramCore, which rules out the account manager. So the screen re-reads the
/// store after every write.
public func arbigramSettingsController(context: AccountContext) -> ViewController {
    let statePromise = ValuePromise(ArbigramSettingsState(accountId: context.account.peerId.id._internalGetInt64Value()), ignoreRepeated: true)

    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = ArbigramSettingsArguments(set: { item, value in
        item.write(value)
        statePromise.set(ArbigramSettingsState(accountId: context.account.peerId.id._internalGetInt64Value()))
    }, openNotificationAccounts: {
        pushControllerImpl?(arbigramNotificationAccountsController(context: context))
    }, openAccounts: {
        pushControllerImpl?(arbigramAccountsController(context: context))
    }, setSecretPhrase: { value in
        ArbigramSettings.shared.secretPhrase = value
        statePromise.set(ArbigramSettingsState(accountId: context.account.peerId.id._internalGetInt64Value()))
    }, openDeletedMessages: {
        pushControllerImpl?(arbigramDeletedMessagesController(context: context))
    })

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [ArbigramSettingsEntry] = []
        for item in ArbigramSwitch.allCases {
            entries.append(.toggle(item, item.value(state)))
            entries.append(.info(item))
        }
        entries.append(.notificationAccounts(state.mutedAccountCount))
        entries.append(.notificationAccountsInfo)
        entries.append(.accounts)
        if state.keepDeletedMessages || state.deletedMessageCount > 0 {
            entries.append(.deletedMessages(state.deletedMessageCount))
        }
        // The row is its own tell: once something is hidden it goes away, so a
        // stranger sees no sign the feature is even configured.
        if !state.hasHiddenAccounts || state.hiddenRevealed {
            entries.append(.secretPhrase(state.secretPhrase))
            entries.append(.secretPhraseInfo)
        }

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Arbigram"),
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
    // The count on the row is read from the store, so coming back from the
    // account list has to re-read it.
    controller.didAppear = { _ in
        statePromise.set(ArbigramSettingsState(accountId: context.account.peerId.id._internalGetInt64Value()))
    }
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    return controller
}

// MARK: - Notifications by account

private final class ArbigramNotificationAccountsArguments {
    let setMuted: (Int64, Bool) -> Void

    init(setMuted: @escaping (Int64, Bool) -> Void) {
        self.setMuted = setMuted
    }
}

private struct ArbigramAccountRow: Equatable {
    let id: Int64
    let title: String
    let enabled: Bool
}

private enum ArbigramNotificationAccountsEntry: ItemListNodeEntry {
    case account(Int, ArbigramAccountRow)
    case info

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case let .account(index, _):
            return Int32(index)
        case .info:
            return 10000
        }
    }

    static func <(lhs: ArbigramNotificationAccountsEntry, rhs: ArbigramNotificationAccountsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ArbigramNotificationAccountsArguments
        switch self {
        case let .account(_, row):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: row.title, value: row.enabled, maximumNumberOfLines: 2, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setMuted(row.id, !value)
            })
        case .info:
            return ItemListTextItem(presentationData: presentationData, text: .plain(loc(presentationData.strings,
                "Выключенный аккаунт снимает свой push-токен с сервера, так что уведомления по нему не отправляются вообще. Сообщения при этом приходят как обычно — их видно, когда откроешь приложение.",
                "An account switched off withdraws its push token from the server, so nothing is sent for it at all. Messages still arrive as usual and are there when the app is opened.")), sectionId: self.section)
        }
    }
}

public func arbigramNotificationAccountsController(context: AccountContext) -> ViewController {
    let mutedPromise = ValuePromise(ArbigramSettings.shared.mutedAccountIds, ignoreRepeated: true)

    let arguments = ArbigramNotificationAccountsArguments(setMuted: { id, muted in
        ArbigramSettings.shared.setAccount(id, muted: muted)
        mutedPromise.set(ArbigramSettings.shared.mutedAccountIds)
    })

    let signal = combineLatest(
        context.sharedContext.presentationData,
        activeAccountsAndPeers(context: context, includePrimary: true),
        mutedPromise.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, accountsAndPeers, mutedAccountIds -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [ArbigramNotificationAccountsEntry] = []
        for (index, item) in accountsAndPeers.1.enumerated() {
            let (accountContext, peer, _) = item
            let id = accountContext.account.peerId.id._internalGetInt64Value()
            let title = peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
            entries.append(.account(index, ArbigramAccountRow(id: id, title: title, enabled: !mutedAccountIds.contains(id))))
        }
        entries.append(.info)

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(loc(presentationData.strings, "Уведомления по аккаунтам", "Notifications by Account")),
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
