#!/usr/bin/env python3
"""
Arbigram — fork patches for Telegram-iOS.

Re-applies every Arbigram change on top of a clean upstream checkout.
Run from the repository root:  python3 arbigram/apply-patches.py

Each patch is anchored to a unique snippet of upstream source. If upstream
moves that snippet, the patch fails loudly instead of silently doing nothing.
"""

import io
import sys

APPLIED = []
FAILED = []


def patch(path, old, new, label):
    try:
        src = io.open(path, encoding='utf-8').read()
    except IOError:
        FAILED.append((label, 'file not found: %s' % path))
        return
    if new in src:
        APPLIED.append((label, 'already applied'))
        return
    if old not in src:
        FAILED.append((label, 'anchor not found in %s' % path))
        return
    io.open(path, 'w', encoding='utf-8', newline='').write(src.replace(old, new, 1))
    APPLIED.append((label, path))


# ---------------------------------------------------------------- 1. accounts
patch(
    'submodules/AccountUtils/Sources/AccountUtils.swift',
    "public let maximumNumberOfAccounts = 3\npublic let maximumPremiumNumberOfAccounts = 4",
    "// ARBIGRAM: raised account limits (upstream: 3 / 4)\n"
    "public let maximumNumberOfAccounts = 10\n"
    "public let maximumPremiumNumberOfAccounts = 10",
    'account limit -> 10',
)

# ----------------------------------------------------------------- 2. stories
patch(
    'submodules/ChatListUI/Sources/ChatListControllerNode.swift',
    """func shouldDisplayStoriesInChatListHeader(storySubscriptions: EngineStorySubscriptions, isHidden: Bool) -> Bool {
    if !storySubscriptions.items.isEmpty {
        return true
    }
    if !isHidden, let accountItem = storySubscriptions.accountItem {
        if accountItem.hasPending || accountItem.storyCount != 0 {
            return true
        }
    }
    return false
}""",
    """func shouldDisplayStoriesInChatListHeader(storySubscriptions: EngineStorySubscriptions, isHidden: Bool) -> Bool {
    // ARBIGRAM: stories strip removed from the chat list header
    return false
}""",
    'stories strip hidden',
)

# --------------------------------------------------------- 3. sponsored posts
AD_PATH = 'submodules/TelegramCore/Sources/TelegramEngine/Messages/AdMessages.swift'
patch(
    AD_PATH,
    "import TelegramApi\n",
    "import TelegramApi\n\n// ARBIGRAM: master switch for sponsored (ad) messages\nprivate let arbigramHideSponsoredMessages = true\n",
    'sponsored switch declared',
)
patch(
    AD_PATH,
    """            guard let inputPeer else {
                return .single((nil, nil, nil, []))
            }""",
    """            // ARBIGRAM: bail out before the sponsored-message request is issued
            guard let inputPeer, !arbigramHideSponsoredMessages else {
                return .single((nil, nil, nil, []))
            }""",
    'sponsored messages never requested',
)

# ---------------------------------------------------------------- 4. peer ids
PI_PATH = 'submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoProfileItems.swift'


def id_row(item_const, value_expr):
    return r'''
        // ARBIGRAM: numeric peer id, tap to copy
        do {
            let arbigramPeerIdText = "\(%s)"
            items[currentPeerInfoSection]!.append(PeerInfoScreenLabeledValueItem(
                id: %s,
                label: "ID",
                text: arbigramPeerIdText,
                textColor: .primary,
                action: { _, _ in
                    UIPasteboard.general.string = arbigramPeerIdText
                    interaction.getController()?.present(UndoOverlayController(
                        presentationData: presentationData,
                        content: .copy(text: "ID copied"),
                        elevatedLayout: false,
                        animateInAsReplacement: false,
                        action: { _ in return false }
                    ), in: .current)
                },
                requestLayout: { animated in
                    interaction.requestLayout(animated)
                }
            ))
        }
''' % (value_expr, item_const)


patch(PI_PATH,
      "import BoostLevelIconComponent\n",
      "import BoostLevelIconComponent\nimport UndoUI // ARBIGRAM\n",
      'peer id: UndoUI import')

patch(PI_PATH,
      "        let ItemAppFooter = 3005\n",
      "        let ItemAppFooter = 3005\n        let ItemArbigramPeerId = 3006 // ARBIGRAM\n",
      'peer id: user constant')

patch(PI_PATH,
      """            }, requestLayout: { animated in
                interaction.requestLayout(animated)
            }))
        }
        if let mainUsername = user.addressName {""",
      """            }, requestLayout: { animated in
                interaction.requestLayout(animated)
            }))
        }
""" + id_row('ItemArbigramPeerId', 'user.id.id._internalGetInt64Value()') + """
        if let mainUsername = user.addressName {""",
      'peer id: user row')

patch(PI_PATH,
      "        let ItemCommunity = 12\n",
      "        let ItemCommunity = 12\n        let ItemArbigramPeerId = 13 // ARBIGRAM\n"
      + id_row('ItemArbigramPeerId', 'channel.id.id._internalGetInt64Value()'),
      'peer id: channel row')

# ------------------------------------------------------------- 5. branding
patch(
    'Telegram/BUILD',
    '''plist_fragment(
    name = "AppNameInfoPlist",
    extension = "plist",
    template =
    """
    <key>CFBundleDisplayName</key>
    <string>Telegram</string>
    """
)''',
    '''plist_fragment(
    name = "AppNameInfoPlist",
    extension = "plist",
    template =
    """
    <key>CFBundleDisplayName</key>
    <string>Arbigram</string>
    """
)''',
    'display name -> Arbigram',
)

patch(
    'Telegram/Telegram-iOS/Config-Fork.xcconfig',
    'APP_NAME=Telegram Fork',
    'APP_NAME=Arbigram',
    'xcconfig name -> Arbigram',
)

# ------------------------------------------------------------------- report
for label, detail in APPLIED:
    print('  ok   %-38s %s' % (label, detail))
for label, detail in FAILED:
    print('  FAIL %-38s %s' % (label, detail))

print('\n%d applied, %d failed' % (len(APPLIED), len(FAILED)))
sys.exit(1 if FAILED else 0)
