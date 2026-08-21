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
    "public let maximumNumberOfAccounts = 30\n"
    "public let maximumPremiumNumberOfAccounts = 30",
    'account limit -> 30',
)

# ----------------------------------------------------------------- 2. stories
CHAT_LIST_PATH = 'submodules/ChatListUI/Sources/ChatListControllerNode.swift'
patch(
    CHAT_LIST_PATH,
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
    // ARBIGRAM: switchable; with the switch off upstream's own rules decide
    if ArbigramSettings.shared.hideStories {
        return false
    }
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
    'stories strip switchable',
)

patch(
    CHAT_LIST_PATH,
    "import AccountContext\nimport SearchBarNode",
    "import AccountContext\nimport ArbigramSettings // ARBIGRAM\nimport SearchBarNode",
    'stories: settings import',
)

patch(
    CHAT_LIST_PATH,
    "    weak var controller: ChatListControllerImpl?",
    """    weak var controller: ChatListControllerImpl?

    // ARBIGRAM: the header is decided during layout rather than from a
    // subscription, so flipping the stories switch has to ask for a new pass.
    private var arbigramSettingsObserver: NSObjectProtocol?""",
    'stories: observer property',
)

patch(
    CHAT_LIST_PATH,
    """        self.controller = controller
        
        super.init()
        
        self.setViewBlock({""",
    """        self.controller = controller
        
        super.init()
        
        self.arbigramSettingsObserver = NotificationCenter.default.addObserver(forName: ArbigramSettings.changedNotification, object: nil, queue: .main) { [weak self] _ in
            self?.controller?.requestLayout(transition: .immediate)
        }
        
        self.setViewBlock({""",
    'stories: observer registered',
)

patch(
    CHAT_LIST_PATH,
    "    init(context: AccountContext, location: ChatListControllerLocation, previewing: Bool,",
    """    // ARBIGRAM
    deinit {
        if let arbigramSettingsObserver = self.arbigramSettingsObserver {
            NotificationCenter.default.removeObserver(arbigramSettingsObserver)
        }
    }
    
    init(context: AccountContext, location: ChatListControllerLocation, previewing: Bool,""",
    'stories: observer released',
)

# --------------------------------------------------------- 3. sponsored posts
AD_PATH = 'submodules/TelegramCore/Sources/TelegramEngine/Messages/AdMessages.swift'
patch(
    AD_PATH,
    "import TelegramApi\n",
    "import TelegramApi\nimport ArbigramSettings\n",
    'sponsored: settings import',
)
patch(
    AD_PATH,
    """            guard let inputPeer else {
                return .single((nil, nil, nil, []))
            }""",
    """            // ARBIGRAM: bail out before the sponsored-message request is issued
            guard let inputPeer, !ArbigramSettings.shared.hideSponsoredMessages else {
                return .single((nil, nil, nil, []))
            }""",
    'sponsored messages never requested',
)

# ---------------------------------------------------------------- 4. peer ids
PI_PATH = 'submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoProfileItems.swift'


def id_row(item_const, value_expr):
    return r'''
        // ARBIGRAM: numeric peer id, tap to copy
        if ArbigramSettings.shared.showPeerId {
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
      "import BoostLevelIconComponent\nimport UndoUI // ARBIGRAM\nimport ArbigramSettings // ARBIGRAM\n",
      'peer id: imports')

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

# AppNameInfoPlist above is wired into the six extensions, not into the app
# target, which takes its name from TelegramInfoPlist. With the extensions
# disabled for single-profile signing, that fragment reaches nothing at all.
patch(
    'Telegram/BUILD',
    '''    <key>CFBundleDisplayName</key>
    <string>Telegram</string>
    <key>CFBundleIdentifier</key>
    <string>{telegram_bundle_id}</string>
    <key>CFBundleName</key>
    <string>Telegram</string>''',
    '''    <!-- ARBIGRAM: the app's own name; AppNameInfoPlist below only reaches the extensions -->
    <key>CFBundleDisplayName</key>
    <string>Arbigram</string>
    <key>CFBundleIdentifier</key>
    <string>{telegram_bundle_id}</string>
    <key>CFBundleName</key>
    <string>Arbigram</string>''',
    'app display name -> Arbigram',
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

# AppDelegate resolves the container in two places. In urlSession(identifier:)
# the bundle id has no other reader, so pinning the group name orphans it, and
# this build treats an unused binding as an error. That site is rewritten first,
# binding and all; the pass below then catches the remaining one, where
# baseAppBundleId is still handed to BuildConfig.
patch(
    'submodules/TelegramUI/Sources/AppDelegate.swift',
    '        let baseAppBundleId = Bundle.main.bundleIdentifier!\n'
    '        let appGroupName = "group.\\(baseAppBundleId)"\n\n'
    '        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)',
    '        // ARBIGRAM: container name comes from the signing profile; upstream derived\n'
    '        // it from the bundle id, which left baseAppBundleId with no other reader here\n'
    '        let appGroupName = "' + APP_GROUP + '"\n\n'
    '        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)',
    'app group: url session lookup pinned',
)

patch(
    'submodules/TelegramUI/Sources/AppDelegate.swift',
    '        let appGroupName = "group.\\(baseAppBundleId)"',
    '        // ARBIGRAM: container name comes from the signing profile\n'
    '        let appGroupName = "' + APP_GROUP + '"',
    'app group: runtime lookup pinned',
    count=0,
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

# ------------------------------------------------- 11. settings screen wiring
# The switches themselves, the store behind them and the screen that shows them
# are Arbigram's own files and travel with the repository. What follows is only
# what has to be threaded through upstream to reach them.

SETTINGS_DEP = '        "//submodules/ArbigramSettings:ArbigramSettings",  # ARBIGRAM'

for build_file, dep_anchor in [
    ('submodules/TelegramCore/BUILD', '        "//submodules/TelegramApi:TelegramApi",'),
    ('submodules/ChatListUI/BUILD', '        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",'),
    ('submodules/TelegramUI/BUILD', '        "//third-party/recaptcha:RecaptchaEnterprise",'),
    ('submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/BUILD', '        "//submodules/AccountContext",'),
]:
    patch(
        build_file,
        dep_anchor + '\n',
        dep_anchor + '\n' + SETTINGS_DEP + '\n',
        'settings: dep in %s' % build_file.split('/')[-2],
    )

# PeerInfoScreen cannot depend on TelegramUI, so the screen is reached through
# the same SharedAccountContext factory the business and energy-saving screens
# use.
patch(
    'submodules/AccountContext/Sources/AccountContext.swift',
    '    func makeBusinessSetupScreen(context: AccountContext) -> ViewController\n',
    '    func makeBusinessSetupScreen(context: AccountContext) -> ViewController\n'
    '    func makeArbigramSettingsScreen(context: AccountContext) -> ViewController // ARBIGRAM\n',
    'settings: factory declared',
)

patch(
    'submodules/TelegramUI/Sources/SharedAccountContext.swift',
    """    public func makeBusinessSetupScreen(context: AccountContext) -> ViewController {
        return PremiumIntroScreen(context: context, mode: .business, source: .settings, modal: false, forceDark: false)
    }""",
    """    public func makeBusinessSetupScreen(context: AccountContext) -> ViewController {
        return PremiumIntroScreen(context: context, mode: .business, source: .settings, modal: false, forceDark: false)
    }
    
    // ARBIGRAM
    public func makeArbigramSettingsScreen(context: AccountContext) -> ViewController {
        return arbigramSettingsController(context: context)
    }""",
    'settings: factory implemented',
)

PEER_INFO_SCREEN = 'submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift'
patch(
    PEER_INFO_SCREEN,
    '    case powerSaving\n',
    '    case powerSaving\n    case arbigram // ARBIGRAM\n',
    'settings: section case',
)

patch(
    'submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenSettingsActions.swift',
    """        case .powerSaving:
            push(energySavingSettingsScreen(context: self.context))""",
    """        case .powerSaving:
            push(energySavingSettingsScreen(context: self.context))
        case .arbigram: // ARBIGRAM
            push(self.context.sharedContext.makeArbigramSettingsScreen(context: self.context))""",
    'settings: section routed',
)

patch(
    'submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift',
    '    let languageName = presentationData.strings.primaryComponent.localizedName',
    """    // ARBIGRAM: the fork's own switches
    items[.advanced]!.append(PeerInfoScreenDisclosureItem(id: 7, text: "Arbigram", icon: PresentationResourcesSettings.arbigram, action: {
        interaction.openSettings(.arbigram)
    }))
    
    let languageName = presentationData.strings.primaryComponent.localizedName""",
    'settings: row in the list',
)

# An existing glyph tinted with the fork's colour, so no new asset is needed.
patch(
    'submodules/TelegramPresentationData/Sources/Resources/PresentationResourcesSettings.swift',
    '    public static let powerSaving = renderSettingsIcon(name: "Item List/Icons/PowerSaving", backgroundColors: [colorOrange])',
    '    public static let powerSaving = renderSettingsIcon(name: "Item List/Icons/PowerSaving", backgroundColors: [colorOrange])\n'
    "    // ARBIGRAM: an existing glyph tinted with the fork's own colour, so no new asset is needed\n"
    '    public static let arbigram = renderSettingsIcon(name: "Item List/Icons/Brush", backgroundColors: [UIColor(rgb: 0x8B6DFF), UIColor(rgb: 0x6C4CF1)])',
    'settings: row icon',
)

# --------------------------------------------------- 12. the other switches
# Read receipts, typing indicators and copy protection each turned out to have
# a single choke point, so none of these is a scattering of call sites.

# Upstream gates every place a read is reported - messages, reactions, stories -
# behind one debug flag, so the switch overlays that flag where it is handed out
# rather than touching the ten places that read it.
patch(
    'submodules/TelegramUI/Sources/SharedAccountContext.swift',
    'import AccountContext\n',
    'import AccountContext\nimport ArbigramSettings\n',
    'switches: shared context import',
)

patch(
    'submodules/TelegramUI/Sources/SharedAccountContext.swift',
    """    public var immediateExperimentalUISettings: ExperimentalUISettings {
        return self.immediateExperimentalUISettingsValue.with { $0 }
    }""",
    """    public var immediateExperimentalUISettings: ExperimentalUISettings {
        var settings = self.immediateExperimentalUISettingsValue.with { $0 }
        // ARBIGRAM: read receipts are switchable; upstream reads this flag in
        // every place a read is reported, so overlaying it here covers them all
        if ArbigramSettings.shared.skipReadHistory {
            settings.skipReadHistory = true
        }
        return settings
    }""",
    'read receipts switchable',
)

ACCOUNT_PATH = 'submodules/TelegramCore/Sources/Account/Account.swift'
patch(
    ACCOUNT_PATH,
    'import EncryptionProvider',
    'import EncryptionProvider\nimport ArbigramSettings',
    'typing: account import',
)

patch(
    'submodules/TelegramCore/Sources/State/PeerInputActivity.swift',
    'public enum PeerInputActivity: Comparable {',
    """public extension PeerInputActivity {
    // ARBIGRAM
    var isArbigramGroupCallSpeaking: Bool {
        if case .speakingInGroupCall = self {
            return true
        }
        return false
    }
}

public enum PeerInputActivity: Comparable {""",
    'typing: group-call test',
)

patch(
    ACCOUNT_PATH,
    """    public func updateLocalInputActivity(peerId: PeerActivitySpace, activity: PeerInputActivity, isPresent: Bool) {
        self.localInputActivityManager.transaction { manager in""",
    """    public func updateLocalInputActivity(peerId: PeerActivitySpace, activity: PeerInputActivity, isPresent: Bool) {
        // ARBIGRAM: only additions are suppressed, so an activity that started
        // before the switch was flipped can still be withdrawn. Group-call
        // speaking drives the call UI rather than a status line, so it stays.
        if isPresent && ArbigramSettings.shared.hideInputActivity && !activity.isArbigramGroupCallSpeaking {
            return
        }
        self.localInputActivityManager.transaction { manager in""",
    'typing indicators switchable',
)

patch(
    ACCOUNT_PATH,
    """    public func acquireLocalInputActivity(peerId: PeerActivitySpace, activity: PeerInputActivity) -> Disposable {
        return self.localInputActivityManager.acquireActivity(chatPeerId: peerId, peerId: self.peerId, activity: activity)
    }""",
    """    public func acquireLocalInputActivity(peerId: PeerActivitySpace, activity: PeerInputActivity) -> Disposable {
        // ARBIGRAM
        if ArbigramSettings.shared.hideInputActivity && !activity.isArbigramGroupCallSpeaking {
            return EmptyDisposable
        }
        return self.localInputActivityManager.acquireActivity(chatPeerId: peerId, peerId: self.peerId, activity: activity)
    }""",
    'recording indicators switchable',
)

# Text selection and media saving hang off the same flag, which is why one
# switch covers both.
patch(
    'submodules/TelegramCore/Sources/Utils/MessageUtils.swift',
    'import TelegramApi',
    'import TelegramApi\nimport ArbigramSettings',
    'copy protection: message import',
)

patch(
    'submodules/TelegramCore/Sources/Utils/MessageUtils.swift',
    """    func isCopyProtected() -> Bool {
        if self.flags.contains(.CopyProtected) {""",
    """    func isCopyProtected() -> Bool {
        // ARBIGRAM
        if ArbigramSettings.shared.ignoreCopyProtection {
            return false
        }
        if self.flags.contains(.CopyProtected) {""",
    'copy protection: per message',
)

patch(
    'submodules/TelegramCore/Sources/Utils/PeerUtils.swift',
    'import Postbox',
    'import Postbox\nimport ArbigramSettings',
    'copy protection: peer import',
)

patch(
    'submodules/TelegramCore/Sources/Utils/PeerUtils.swift',
    """    var isCopyProtectionEnabled: Bool {
        switch self {
        case let group as TelegramGroup:""",
    """    var isCopyProtectionEnabled: Bool {
        // ARBIGRAM: text selection and media saving both hang off this flag
        if ArbigramSettings.shared.ignoreCopyProtection {
            return false
        }
        switch self {
        case let group as TelegramGroup:""",
    'copy protection: per peer',
)

# ----------------------------------------------------------------- 13. theme
# The look itself lives in TelegramPresentationData/Sources/ArbigramTheme.swift,
# which is the fork's own file. What follows is only what upstream has to be
# told about it.
PRESETS_PATH = 'submodules/SettingsUI/Sources/Themes/ThemeColorPresets.swift'
patch(
    PRESETS_PATH,
    """var dayClassicColorPresets: [PresentationThemeAccentColor] = [
    // Pink with Blue""",
    """var dayClassicColorPresets: [PresentationThemeAccentColor] = [
    // ARBIGRAM: first in the row, and what the one-time migration applies
    arbigramAccentColor(dark: false),

    // Pink with Blue""",
    'theme: classic preset',
)

patch(
    PRESETS_PATH,
    """var dayColorPresets: [PresentationThemeAccentColor] = [
    PresentationThemeAccentColor(index: 101,""",
    """var dayColorPresets: [PresentationThemeAccentColor] = [
    arbigramAccentColor(dark: false), // ARBIGRAM
    PresentationThemeAccentColor(index: 101,""",
    'theme: day preset',
)

patch(
    PRESETS_PATH,
    'var nightColorPresets: [PresentationThemeAccentColor] = [\n',
    'var nightColorPresets: [PresentationThemeAccentColor] = [\n    arbigramAccentColor(dark: true), // ARBIGRAM\n',
    'theme: night preset',
)

# defaultSettings would only ever reach a fresh install, and an update installs
# over settings that already exist, so the theme is applied once rather than
# defaulted.
patch(
    'submodules/TelegramUI/Sources/SharedAccountContext.swift',
    """        let immediateExperimentalUISettingsValue = self.immediateExperimentalUISettingsValue
        let _ = immediateExperimentalUISettingsValue.swap(initialPresentationDataAndSettings.experimentalUISettings)
""",
    """        // ARBIGRAM: the fork's themes are local themes, and a local theme is
        // read back out of the media box by its resource, so both have to be
        // written there before anything can select one. Rewritten on every
        // launch rather than once, so an edited definition ships with a build
        // instead of being stuck behind a first-run flag.
        for arbigramTheme in ArbigramTheme.allCases {
            if let data = arbigramTheme.encoded() {
                self.accountManager.mediaBox.storeResourceData(arbigramTheme.resource.id, data: data, synchronous: true)
            }
        }

        // Selecting one, on the other hand, happens once. defaultSettings would
        // only reach a fresh install, and an update installs over settings that
        // already exist. After this the theme belongs to Appearance and is
        // never forced again.
        if !ArbigramSettings.shared.didApplyTheme {
            ArbigramSettings.shared.didApplyTheme = true
            let _ = updatePresentationThemeSettingsInteractively(accountManager: self.accountManager, { current in
                var current = current
                var accentColors = current.themeSpecificAccentColors
                accentColors[PresentationThemeReference.builtin(.dayClassic).index] = arbigramAccentColor(dark: false)
                accentColors[PresentationThemeReference.builtin(.day).index] = arbigramAccentColor(dark: false)
                accentColors[PresentationThemeReference.builtin(.night).index] = arbigramAccentColor(dark: true)
                accentColors[PresentationThemeReference.builtin(.nightAccent).index] = arbigramAccentColor(dark: true)
                current.themeSpecificAccentColors = accentColors
                // A wallpaper already chosen for a theme wins over the theme's
                // own, which would leave the new look half-applied.
                current.themeSpecificChatWallpapers = [:]
                current.theme = ArbigramTheme.violet.reference
                current.automaticThemeSwitchSetting = AutomaticThemeSwitchSetting(force: current.automaticThemeSwitchSetting.force, trigger: current.automaticThemeSwitchSetting.trigger, theme: ArbigramTheme.midnight.reference)
                return current
            }).start()
        }

        let immediateExperimentalUISettingsValue = self.immediateExperimentalUISettingsValue
        let _ = immediateExperimentalUISettingsValue.swap(initialPresentationDataAndSettings.experimentalUISettings)
""",
    'theme: applied once on update',
)



# The two themes are local themes, listed next to the builtin ones. Without this
# a local theme only shows up in Appearance while it is the active one.
THEME_LIST_OLD = """        var defaultThemes: [PresentationThemeReference] = []
        if presentationData.autoNightModeTriggered {
            defaultThemes.append(contentsOf: [.builtin(.nightAccent), .builtin(.night)])
        } else {
            defaultThemes.append(contentsOf: [
                .builtin(.dayClassic),
                .builtin(.nightAccent),
                .builtin(.day),
                .builtin(.night)
            ])
        }"""

THEME_LIST_NEW = """        var defaultThemes: [PresentationThemeReference] = []
        // ARBIGRAM: the fork's own themes, listed alongside the builtin ones.
        // Without this a local theme only appears while it is the active one.
        if presentationData.autoNightModeTriggered {
            defaultThemes.append(ArbigramTheme.midnight.reference)
            defaultThemes.append(contentsOf: [.builtin(.nightAccent), .builtin(.night)])
        } else {
            defaultThemes.append(contentsOf: [
                ArbigramTheme.violet.reference,
                ArbigramTheme.midnight.reference,
                .builtin(.dayClassic),
                .builtin(.nightAccent),
                .builtin(.day),
                .builtin(.night)
            ])
        }"""

for theme_list_file in [
    'submodules/SettingsUI/Sources/ThemePickerController.swift',
    'submodules/SettingsUI/Sources/Themes/ThemeSettingsController.swift',
]:
    patch(
        theme_list_file,
        THEME_LIST_OLD,
        THEME_LIST_NEW,
        'theme: listed in %s' % theme_list_file.split('/')[-1].replace('.swift', ''),
    )

# ---------------------------------------------------------- 14. contacts tab
# Calls already has an upstream switch. The tab bar is rebuilt on demand rather
# than observed, so the root controller keeps the last calls-tab value to
# rebuild itself when a switch changes.
ROOT_PATH = 'submodules/TelegramUI/Sources/TelegramRootController.swift'
patch(
    ROOT_PATH,
    'import AccountContext\n',
    'import AccountContext\nimport ArbigramSettings\n',
    'contacts tab: import',
)

patch(
    ROOT_PATH,
    '    public var contactsController: ContactsController?',
    """    public var contactsController: ContactsController?

    // ARBIGRAM: the tab bar is rebuilt on demand rather than observed, so the
    // last calls-tab value is kept to rebuild it when a switch changes.
    private var arbigramShowCallsTab: Bool = false
    private var arbigramSettingsObserver: NSObjectProtocol?""",
    'contacts tab: observer state',
)

patch(
    ROOT_PATH,
    """    deinit {
        self.permissionsDisposable?.dispose()
        self.presentationDataDisposable?.dispose()
        self.applicationInFocusDisposable?.dispose()
        self.storyUploadEventsDisposable?.dispose()
    }""",
    """    deinit {
        self.permissionsDisposable?.dispose()
        self.presentationDataDisposable?.dispose()
        self.applicationInFocusDisposable?.dispose()
        self.storyUploadEventsDisposable?.dispose()
        // ARBIGRAM
        if let arbigramSettingsObserver = self.arbigramSettingsObserver {
            NotificationCenter.default.removeObserver(arbigramSettingsObserver)
        }
    }""",
    'contacts tab: observer released',
)

patch(
    ROOT_PATH,
    '    public func addRootControllers(showCallsTab: Bool) {',
    """    public func addRootControllers(showCallsTab: Bool) {
        self.arbigramShowCallsTab = showCallsTab // ARBIGRAM
        if self.arbigramSettingsObserver == nil {
            self.arbigramSettingsObserver = NotificationCenter.default.addObserver(forName: ArbigramSettings.changedNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else {
                    return
                }
                self.updateRootControllers(showCallsTab: self.arbigramShowCallsTab)
            }
        }""",
    'contacts tab: observer registered',
)

patch(
    ROOT_PATH,
    """        controllers.append(contactsController)
        
        if showCallsTab {""",
    """        if !ArbigramSettings.shared.hideContactsTab { // ARBIGRAM
            controllers.append(contactsController)
        }
        
        if showCallsTab {""",
    'contacts tab: hidden at startup',
)

patch(
    ROOT_PATH,
    """    public func updateRootControllers(showCallsTab: Bool) {
        guard let rootTabController = self.rootTabController as? TabBarControllerImpl else {
            return
        }
        var controllers: [ViewController] = []
        controllers.append(self.contactsController!)
        if showCallsTab {""",
    """    public func updateRootControllers(showCallsTab: Bool) {
        self.arbigramShowCallsTab = showCallsTab // ARBIGRAM
        guard let rootTabController = self.rootTabController as? TabBarControllerImpl else {
            return
        }
        var controllers: [ViewController] = []
        if !ArbigramSettings.shared.hideContactsTab, let contactsController = self.contactsController { // ARBIGRAM
            controllers.append(contactsController)
        }
        if showCallsTab {""",
    'contacts tab: hidden on update',
)

# ------------------------------------------------------------------- report
for label, detail in APPLIED:
    print('  ok   %-38s %s' % (label, detail))
for label, detail in FAILED:
    print('  FAIL %-38s %s' % (label, detail))

print('\n%d applied, %d failed' % (len(APPLIED), len(FAILED)))
sys.exit(1 if FAILED else 0)
