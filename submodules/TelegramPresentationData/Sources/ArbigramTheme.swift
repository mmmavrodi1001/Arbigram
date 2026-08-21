import Foundation
import UIKit
import Postbox
import TelegramCore
import TelegramUIPreferences

/// The fork's own themes.
///
/// They are local themes rather than new builtin ones.
/// PresentationBuiltinThemeReference is a persisted Int32 that also maps onto
/// TelegramBaseTheme, the server's own idea of a base theme, so a fifth case
/// there would have to answer what it means to a cloud theme — for nothing, since
/// a local theme already carries every colour the app draws with, plus a name of
/// its own in the picker.
///
/// Both are written to the account manager's media box under fixed resource ids.
/// Fixed, because a local theme is addressed by its resource: a random id would
/// mean a new theme on every launch, piling up in the picker, and the reference
/// the picker lists could not be reconstructed without storing it somewhere.
public enum ArbigramTheme: CaseIterable {
    case violet
    case midnight

    public var title: String {
        switch self {
        case .violet:
            return "Arbigram Violet"
        case .midnight:
            return "Arbigram Midnight"
        }
    }

    /// Chosen once and never changed; see the note on the type.
    public var fileId: Int64 {
        switch self {
        case .violet:
            return 7331002026080801
        case .midnight:
            return 7331002026080802
        }
    }

    public var isDark: Bool {
        switch self {
        case .violet:
            return false
        case .midnight:
            return true
        }
    }

    public var wallpaper: TelegramWallpaper {
        switch self {
        case .violet:
            return defaultBuiltinWallpaper(data: .variant14, colors: [0xe6ddff, 0xb9a6f5, 0xd7c6ff, 0x9d84ee], intensity: 50, rotation: nil)
        case .midnight:
            // Negative intensity puts the pattern under a dark gradient rather
            // than over a light one.
            return defaultBuiltinWallpaper(data: .variant14, colors: [0x241a45, 0x4a3a8c, 0x2f2456, 0x5b3fd6], intensity: -40, rotation: nil)
        }
    }

    public var accentColor: UIColor {
        switch self {
        case .violet:
            return UIColor(rgb: 0x6c4cf1)
        case .midnight:
            return UIColor(rgb: 0x8b6dff)
        }
    }

    public var bubbleColors: [UInt32] {
        switch self {
        case .violet:
            return [0xe6dcff, 0xf2ebff]
        case .midnight:
            return [0x8b6dff, 0x6c4cf1]
        }
    }

    public var resource: LocalFileMediaResource {
        return LocalFileMediaResource(fileId: self.fileId)
    }

    public var reference: PresentationThemeReference {
        return .local(PresentationLocalTheme(title: self.title, resource: self.resource, resolvedWallpaper: self.wallpaper))
    }

    public func makeTheme() -> PresentationTheme {
        let base = makeDefaultPresentationTheme(reference: self.isDark ? .night : .dayClassic, extendingThemeReference: nil, serviceBackgroundColor: nil, preview: false)
        return customizePresentationTheme(
            base,
            editing: false,
            title: self.title,
            accentColor: self.accentColor,
            outgoingAccentColor: nil,
            backgroundColors: [],
            bubbleColors: self.bubbleColors,
            animateBubbleColors: true,
            wallpaper: self.wallpaper
        )
    }

    /// The theme serialised the way a .tgios-theme file holds it, which is what
    /// makePresentationTheme reads back out of the media box.
    public func encoded() -> Data? {
        guard let string = encodePresentationTheme(self.makeTheme()) else {
            return nil
        }
        return string.data(using: .utf8)
    }
}

/// The accent that matches the themes, for the colour row in Appearance. Kept
/// separate because an accent applies on top of a builtin theme, which is what
/// someone who prefers a stock theme with the fork's colour wants.
public let arbigramAccentColorIndex: Int32 = 108

public func arbigramAccentColor(dark: Bool) -> PresentationThemeAccentColor {
    let theme: ArbigramTheme = dark ? .midnight : .violet
    return PresentationThemeAccentColor(
        index: arbigramAccentColorIndex,
        baseColor: .preset,
        accentColor: dark ? 0x8b6dff : 0x6c4cf1,
        bubbleColors: theme.bubbleColors,
        wallpaper: theme.wallpaper
    )
}
