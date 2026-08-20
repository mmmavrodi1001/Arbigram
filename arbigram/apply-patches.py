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

# The signing profile grants a fixed set of app-group containers whose names are
# unrelated to the bundle id, so both the entitlement and the runtime lookup are
# pinned to one of them. Change this if the profile changes.
APP_GROUP = 'group.dfbc88d056a46f1b.1'


def patch(path, old, new, label, count=1):
    """Replace `old` with `new` in `path`. count=0 replaces every occurrence."""
    try:
        src = io.open(path, encoding='utf-8').read()
    except IOError:
        FAILED.append((label, 'file not found: %s' % path))
        return
    # `new` often contains `old` (a patch that inserts around its anchor), so
    # re-running must not append a second copy. count=0 is the exception: it
    # rewrites every remaining site, which is how partially-applied multi-site
    # patches finish.
    if new in src and count != 0:
        APPLIED.append((label, 'already applied'))
        return
    if old not in src:
        # Nothing left to rewrite: either the patch is already in, or the
        # upstream snippet this patch is anchored to has moved.
        APPLIED.append((label, 'already applied')) if new in src else \
            FAILED.append((label, 'anchor not found in %s' % path))
        return
    io.open(path, 'w', encoding='utf-8', newline='').write(
        src.replace(old, new, -1 if count == 0 else count))
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

# ------------------------------------------------------------------ 6. icon
# Upstream ships an Icon Composer bundle (Telegram.icon) assembled from layered
# SVGs. Arbigram has a flat raster icon, so the app switches to a classic
# .appiconset — the format actool has understood for a decade.
ICON_FILEGROUP = '\n'.join([
    'composer_icon_folders = ["Telegram"]',
    '',
    '# ARBIGRAM: raster app icon',
    'filegroup(',
    '    name = "ArbigramIcon",',
    '    srcs = glob([',
    '        "Telegram-iOS/AppIcons.xcassets/ArbigramIcon.appiconset/*",',
    '    ]),',
    ')',
    '',
])

patch(
    'Telegram/BUILD',
    'composer_icon_folders = ["Telegram"]\n',
    ICON_FILEGROUP,
    'icon: filegroup declared',
)

patch(
    'Telegram/BUILD',
    '    app_icons = [ ":{}_icon".format(name) for name in composer_icon_folders ],',
    '    app_icons = [":ArbigramIcon"],  # ARBIGRAM',
    'icon: app uses the Arbigram icon set',
)

# ------------------------------------------------- 7. single-profile signing
# The signing profile covers exactly one application id, so the six app
# extensions (share sheet, notifications, widgets, Siri, broadcast) cannot be
# signed and are dropped from the build.
patch(
    'Telegram/BUILD',
    """    extensions = select({
        ":disableExtensionsSetting": [],
        "//conditions:default": [
            ":ShareExtension",
            ":NotificationContentExtension",
            ":NotificationServiceExtension" + notificationServiceExtensionVersion,
            ":IntentsExtension",
            ":WidgetExtension",
            ":BroadcastUploadExtension",
        ],
    }),""",
    """    # ARBIGRAM: no app extensions — the signing profile covers one app id only
    extensions = [],""",
    'signing: app extensions dropped',
)

# --------------------------------------------------------------- 8. app group
# Upstream derives the shared container name from the bundle id
# ("group." + bundle id). The signing profile grants differently named
# containers, so the entitlement and the runtime lookup both move to APP_GROUP.
patch(
    'Telegram/BUILD',
    '        <string>group.{telegram_bundle_id}</string>',
    '        <string>' + APP_GROUP + '</string>  <!-- ARBIGRAM -->',
    'app group: entitlement pinned',
)

patch(
    'submodules/TelegramUI/Sources/AppDelegate.swift',
    '        let appGroupName = "group.\\(baseAppBundleId)"',
    '        // ARBIGRAM: container name comes from the signing profile\n'
    '        let appGroupName = "' + APP_GROUP + '"',
    'app group: runtime lookup pinned',
    count=0,  # AppDelegate resolves the container in more than one place
)

patch(
    'submodules/DebugSettingsUI/Sources/DebugController.swift',
    '    let appGroupName = "group.\\(Bundle.main.bundleIdentifier!)"',
    '    // ARBIGRAM: container name comes from the signing profile\n'
    '    let appGroupName = "' + APP_GROUP + '"',
    'app group: debug screen lookup pinned',
)

# ------------------------------------------------------ 9. certificate import
# Upstream imports signing certificates with an empty password, which is right
# for its own fake self-signed pair. A real .p12 from a signing service is
# password-protected, so the password is read from the environment instead.
patch(
    'build-system/Make/ImportCertificates.py',
    "                '-P',\n                '',",
    "                '-P',\n"
    "                # ARBIGRAM: real certificates ship with a password\n"
    "                os.environ.get('CODESIGNING_P12_PASSWORD', ''),",
    'codesigning: p12 password from env',
)

# ------------------------------------------------------------ 10. submodules
# Two submodules are declared with URLs relative to the repository they sit in
# ("../rlottie.git"). In TelegramMessenger/Telegram-iOS that resolves to the
# Telegram org; in a fork it resolves to the fork owner's account, where those
# repositories do not exist, and checkout dies with a 404. Pin them absolutely.
patch(
    '.gitmodules',
    '\turl=../rlottie.git',
    '\turl = https://github.com/TelegramMessenger/rlottie.git',
    'submodules: rlottie url absolute',
)

patch(
    '.gitmodules',
    'url=../tgcalls.git',
    'url = https://github.com/TelegramMessenger/tgcalls.git',
    'submodules: tgcalls url absolute',
)

# ------------------------------------------------------------------- report
for label, detail in APPLIED:
    print('  ok   %-38s %s' % (label, detail))
for label, detail in FAILED:
    print('  FAIL %-38s %s' % (label, detail))

print('\n%d applied, %d failed' % (len(APPLIED), len(FAILED)))
sys.exit(1 if FAILED else 0)
