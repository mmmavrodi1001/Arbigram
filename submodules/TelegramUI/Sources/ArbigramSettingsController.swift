import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import ArbigramSettings

private enum ArbigramSettingsSection: Int32 {
    case stories
    case sponsored
    case peerId
}

private final class ArbigramSettingsArguments {
    let setHideStories: (Bool) -> Void
    let setHideSponsoredMessages: (Bool) -> Void
    let setShowPeerId: (Bool) -> Void

    init(
        setHideStories: @escaping (Bool) -> Void,
        setHideSponsoredMessages: @escaping (Bool) -> Void,
        setShowPeerId: @escaping (Bool) -> Void
    ) {
        self.setHideStories = setHideStories
        self.setHideSponsoredMessages = setHideSponsoredMessages
        self.setShowPeerId = setShowPeerId
    }
}

private enum ArbigramSettingsEntry: ItemListNodeEntry {
    case hideStories(Bool)
    case hideStoriesInfo
    case hideSponsoredMessages(Bool)
    case hideSponsoredMessagesInfo
    case showPeerId(Bool)
    case showPeerIdInfo

    var section: ItemListSectionId {
        switch self {
        case .hideStories, .hideStoriesInfo:
            return ArbigramSettingsSection.stories.rawValue
        case .hideSponsoredMessages, .hideSponsoredMessagesInfo:
            return ArbigramSettingsSection.sponsored.rawValue
        case .showPeerId, .showPeerIdInfo:
            return ArbigramSettingsSection.peerId.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .hideStories:
            return 0
        case .hideStoriesInfo:
            return 1
        case .hideSponsoredMessages:
            return 2
        case .hideSponsoredMessagesInfo:
            return 3
        case .showPeerId:
            return 4
        case .showPeerIdInfo:
            return 5
        }
    }

    static func <(lhs: ArbigramSettingsEntry, rhs: ArbigramSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ArbigramSettingsArguments
        switch self {
        case let .hideStories(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Stories", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setHideStories(value)
            })
        case .hideStoriesInfo:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Removes the stories strip above the chat list."), sectionId: self.section)
        case let .hideSponsoredMessages(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Sponsored Messages", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setHideSponsoredMessages(value)
            })
        case .hideSponsoredMessagesInfo:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Ads are never requested from the server rather than hidden after arriving. Chats already open keep their current state until reopened."), sectionId: self.section)
        case let .showPeerId(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Show ID in Profiles", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setShowPeerId(value)
            })
        case .showPeerIdInfo:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Adds the numeric identifier to user, group and channel profiles. Tap it to copy."), sectionId: self.section)
        }
    }
}

private struct ArbigramSettingsState: Equatable {
    var hideStories: Bool
    var hideSponsoredMessages: Bool
    var showPeerId: Bool

    init() {
        self.hideStories = ArbigramSettings.shared.hideStories
        self.hideSponsoredMessages = ArbigramSettings.shared.hideSponsoredMessages
        self.showPeerId = ArbigramSettings.shared.showPeerId
    }
}

private func arbigramSettingsEntries(state: ArbigramSettingsState) -> [ArbigramSettingsEntry] {
    return [
        .hideStories(state.hideStories),
        .hideStoriesInfo,
        .hideSponsoredMessages(state.hideSponsoredMessages),
        .hideSponsoredMessagesInfo,
        .showPeerId(state.showPeerId),
        .showPeerIdInfo,
    ]
}

/// The switches are not backed by a signal — the store has to be readable from
/// TelegramCore, which rules out the account manager. So the screen mirrors the
/// store into its own state and writes through on every change.
public func arbigramSettingsController(context: AccountContext) -> ViewController {
    let statePromise = ValuePromise(ArbigramSettingsState(), ignoreRepeated: true)
    let stateValue = Atomic(value: ArbigramSettingsState())
    let updateState: ((inout ArbigramSettingsState) -> Void) -> Void = { f in
        statePromise.set(stateValue.modify { current in
            var updated = current
            f(&updated)
            return updated
        })
    }

    let arguments = ArbigramSettingsArguments(setHideStories: { value in
        ArbigramSettings.shared.hideStories = value
        updateState { $0.hideStories = value }
    }, setHideSponsoredMessages: { value in
        ArbigramSettings.shared.hideSponsoredMessages = value
        updateState { $0.hideSponsoredMessages = value }
    }, setShowPeerId: { value in
        ArbigramSettings.shared.showPeerId = value
        updateState { $0.showPeerId = value }
    })

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Arbigram"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: arbigramSettingsEntries(state: state),
            style: .blocks
        )
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
