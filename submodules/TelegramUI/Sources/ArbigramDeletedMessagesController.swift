import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import TelegramStringFormatting
import ItemListUI
import PresentationDataUtils
import AccountContext
import ArbigramSettings

private final class ArbigramDeletedMessagesArguments {
    let clear: () -> Void

    init(clear: @escaping () -> Void) {
        self.clear = clear
    }
}

private enum ArbigramDeletedMessagesEntry: ItemListNodeEntry {
    case message(Int, String, String)
    case empty(String)
    case clear(String)
    case info(String)

    var section: ItemListSectionId {
        switch self {
        case .message, .empty:
            return 0
        case .clear, .info:
            return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case let .message(index, _, _):
            return Int32(index)
        case .empty:
            return 9000
        case .clear:
            return 10000
        case .info:
            return 10001
        }
    }

    static func <(lhs: ArbigramDeletedMessagesEntry, rhs: ArbigramDeletedMessagesEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ArbigramDeletedMessagesArguments
        switch self {
        case let .message(_, title, text):
            return ItemListMultilineTextItem(presentationData: presentationData, text: title + "\n" + text, enabledEntityTypes: [], sectionId: self.section, style: .blocks)
        case let .empty(text), let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .clear(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.clear()
            })
        }
    }
}

private struct ArbigramDeletedMessagesState: Equatable {
    var revision: Int = 0
}

public func arbigramDeletedMessagesController(context: AccountContext) -> ViewController {
    let statePromise = ValuePromise(ArbigramDeletedMessagesState(), ignoreRepeated: true)
    let stateValue = Atomic(value: ArbigramDeletedMessagesState())

    let arguments = ArbigramDeletedMessagesArguments(clear: {
        ArbigramSettings.shared.clearDeletedMessages()
        statePromise.set(stateValue.modify { current in
            var updated = current
            updated.revision += 1
            return updated
        })
    })

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        // Newest first: the interesting one is always the one that just went.
        let records = ArbigramSettings.shared.deletedMessages.reversed()

        var entries: [ArbigramDeletedMessagesEntry] = []
        if records.isEmpty {
            entries.append(.empty(isRussian
                ? "Пока пусто. Сюда попадают входящие сообщения, которые собеседник удалил после того, как ты их получил."
                : "Nothing yet. Incoming messages the other side deletes after they reached you land here."))
        } else {
            for (index, record) in records.enumerated() {
                var title = record.chatTitle
                if !record.authorTitle.isEmpty && record.authorTitle != record.chatTitle {
                    title += " · " + record.authorTitle
                }
                title += " · " + stringForFullDate(timestamp: record.timestamp, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat)

                var text = record.text
                if !record.mediaKind.isEmpty {
                    let kind = "[" + record.mediaKind + "]"
                    text = text.isEmpty ? kind : kind + " " + text
                }
                entries.append(.message(index, title, text))
            }
            entries.append(.clear(isRussian ? "Очистить" : "Clear"))
        }
        entries.append(.info(isRussian
            ? "Хранятся последние \(ArbigramSettings.deletedMessagesLimit) сообщений, только текст и вид вложения. Само сообщение удаляется как обычно — здесь остаётся копия записи, а не сообщение в чате."
            : "The last \(ArbigramSettings.deletedMessagesLimit) are kept, text and attachment kind only. The message itself is deleted as usual; what stays here is a copy of the record, not a message in the chat."))

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(isRussian ? "Удалённые сообщения" : "Deleted Messages"),
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
    controller.didAppear = { _ in
        statePromise.set(stateValue.modify { current in
            var updated = current
            updated.revision += 1
            return updated
        })
    }
    return controller
}
