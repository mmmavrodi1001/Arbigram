import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import ArbigramSettings

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
}

private final class ArbigramSettingsArguments {
    let set: (ArbigramSwitch, Bool) -> Void

    init(set: @escaping (ArbigramSwitch, Bool) -> Void) {
        self.set = set
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

    var section: ArbigramSettingsSection {
        switch self {
        case .hideStories: return .stories
        case .hideSponsoredMessages: return .sponsored
        case .showPeerId: return .peerId
        case .skipReadHistory: return .readReceipts
        case .hideInputActivity: return .inputActivity
        case .ignoreCopyProtection: return .copyProtection
        case .hideContactsTab: return .contactsTab
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
        }
    }
}

private enum ArbigramSettingsEntry: ItemListNodeEntry {
    case toggle(ArbigramSwitch, Bool)
    case info(ArbigramSwitch)

    var section: ItemListSectionId {
        switch self {
        case let .toggle(item, _):
            return item.section.rawValue
        case let .info(item):
            return item.section.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case let .toggle(item, _):
            return item.rawValue * 2
        case let .info(item):
            return item.rawValue * 2 + 1
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

    init() {
        let settings = ArbigramSettings.shared
        self.hideStories = settings.hideStories
        self.hideSponsoredMessages = settings.hideSponsoredMessages
        self.showPeerId = settings.showPeerId
        self.skipReadHistory = settings.skipReadHistory
        self.hideInputActivity = settings.hideInputActivity
        self.ignoreCopyProtection = settings.ignoreCopyProtection
        self.hideContactsTab = settings.hideContactsTab
    }
}

/// The switches are not backed by a signal — the store has to be readable from
/// TelegramCore, which rules out the account manager. So the screen re-reads the
/// store after every write.
public func arbigramSettingsController(context: AccountContext) -> ViewController {
    let statePromise = ValuePromise(ArbigramSettingsState(), ignoreRepeated: true)

    let arguments = ArbigramSettingsArguments(set: { item, value in
        item.write(value)
        statePromise.set(ArbigramSettingsState())
    })

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [ArbigramSettingsEntry] = []
        for item in ArbigramSwitch.allCases {
            entries.append(.toggle(item, item.value(state)))
            entries.append(.info(item))
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

    return ItemListController(context: context, state: signal)
}
