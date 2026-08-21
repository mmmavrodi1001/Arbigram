import Foundation
import TelegramUIPreferences

/// The fork's own look.
///
/// It is expressed as an accent colour rather than a fifth builtin theme.
/// PresentationBuiltinThemeReference is a persisted Int32 enum switched over in
/// a dozen places — codable, base-theme mapping, customisation, the picker —
/// and a new case there is a wide change for no gain. An accent carries an
/// accent colour, a bubble gradient and a wallpaper, which is everything the
/// builtin themes differ by anyway, and it stays reversible: Appearance
/// switches away from it and back like any other preset.
///
/// Day and night are separate values because a violet that reads on white does
/// not read on black.
public let arbigramAccentColorIndex: Int32 = 108

public func arbigramAccentColor(dark: Bool) -> PresentationThemeAccentColor {
    if dark {
        return PresentationThemeAccentColor(
            index: arbigramAccentColorIndex,
            baseColor: .preset,
            accentColor: 0x8b6dff,
            bubbleColors: [0x8b6dff, 0x6c4cf1],
            // Negative intensity puts the pattern under a dark gradient rather
            // than over a light one.
            wallpaper: defaultBuiltinWallpaper(data: .variant14, colors: [0x2b1f52, 0x4b3a8f, 0x35275f, 0x6c4cf1], intensity: -35, rotation: nil)
        )
    } else {
        return PresentationThemeAccentColor(
            index: arbigramAccentColorIndex,
            baseColor: .preset,
            accentColor: 0xff6c4cf1,
            bubbleColors: [0xffe6dcff, 0xfff2ebff],
            wallpaper: defaultBuiltinWallpaper(data: .variant14, colors: [0xe6ddff, 0xb9a6f5, 0xd7c6ff, 0x9d84ee], intensity: 50, rotation: nil)
        )
    }
}
