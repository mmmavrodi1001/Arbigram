import Foundation
import UIKit
import Photos
import Display
import SwiftSignalKit
import TelegramPresentationData
import TelegramStringFormatting
import ItemListUI
import PresentationDataUtils
import AccountContext
import UndoUI
import ArbigramSettings

/// The attachment is a plain file in the fork's own folder by the time it gets
/// here, not a Telegram media reference, so the camera roll is asked directly
/// rather than through the app's own saving path.
private func arbigramSaveFileToCameraRoll(path: String, isVideo: Bool, completion: @escaping (Bool) -> Void) {
    PHPhotoLibrary.requestAuthorization { status in
        // .limited arrived in iOS 14 and this app still targets 13.
        var allowed = status == .authorized
        if #available(iOS 14.0, *) {
            allowed = allowed || status == .limited
        }
        guard allowed else {
            Queue.mainQueue().async {
                completion(false)
            }
            return
        }
        PHPhotoLibrary.shared().performChanges({
            if isVideo {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: URL(fileURLWithPath: path))
            } else {
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: URL(fileURLWithPath: path))
            }
        }, completionHandler: { success, _ in
            Queue.mainQueue().async {
                completion(success)
            }
        })
    }
}

private final class ArbigramDeletedMessagesArguments {
    let clear: () -> Void
    let saveMedia: (String, Bool) -> Void

    init(clear: @escaping () -> Void, saveMedia: @escaping (String, Bool) -> Void) {
        self.clear = clear
        self.saveMedia = saveMedia
    }
}

private enum ArbigramDeletedMessagesEntry: ItemListNodeEntry {
    case message(Int, String, String, String?, Bool)
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
        case let .message(index, _, _, _, _):
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
        case let .message(_, title, text, mediaFile, isVideo):
            return ItemListMultilineTextItem(presentationData: presentationData, text: title + "\n" + text, enabledEntityTypes: [], sectionId: self.section, style: .blocks, action: mediaFile.flatMap { file in
                return {
                    arguments.saveMedia(file, isVideo)
                }
            })
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

    var presentImpl: ((ViewController) -> Void)?

    let arguments = ArbigramDeletedMessagesArguments(clear: {
        ArbigramSettings.shared.clearDeletedMessages()
        statePromise.set(stateValue.modify { current in
            var updated = current
            updated.revision += 1
            return updated
        })
    }, saveMedia: { file, isVideo in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        guard let path = ArbigramSettings.shared.deletedMediaPath(file), FileManager.default.fileExists(atPath: path) else {
            presentImpl?(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: isRussian ? "Файл не сохранился" : "The file was not kept", timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }))
            return
        }
        arbigramSaveFileToCameraRoll(path: path, isVideo: isVideo, completion: { success in
            let text: String
            if success {
                text = isRussian ? "Сохранено в галерею" : "Saved to your photos"
            } else {
                text = isRussian ? "Не удалось сохранить" : "Could not save"
            }
            presentImpl?(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }))
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
                    var kind = "[" + record.mediaKind + "]"
                    if record.mediaFile != nil {
                        kind += isRussian ? " — нажми, чтобы сохранить" : " — tap to save"
                    }
                    text = text.isEmpty ? kind : kind + " " + text
                }
                let isVideo = record.mediaKind == "video" || record.mediaKind == "round"
                entries.append(.message(index, title, text, record.mediaFile, isVideo))
            }
            entries.append(.clear(isRussian ? "Очистить" : "Clear"))
        }
        entries.append(.info(isRussian
            ? "Хранятся последние \(ArbigramSettings.deletedMessagesLimit) сообщений. Вложение сохраняется, если успело загрузиться до удаления — нажми на запись, чтобы положить его в галерею. Само сообщение из чата исчезает как обычно."
            : "The last \(ArbigramSettings.deletedMessagesLimit) are kept. An attachment is kept if it had finished downloading before the delete arrived — tap a record to put it in your photos. The message itself leaves the chat as usual."))

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
    presentImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    controller.didAppear = { _ in
        statePromise.set(stateValue.modify { current in
            var updated = current
            updated.revision += 1
            return updated
        })
    }
    return controller
}
