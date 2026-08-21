#!/usr/bin/env python3
"""
Arbigram — regenerate the app icon set from arbigram/icon/source-1024.png.

Run from the repository root:  python3 arbigram/make-icon.py

Only sizes that iOS 13 and later actually use are emitted. In particular there
is no 76x76@1x: that slot exists solely for non-Retina iPads, none of which run
anything past iOS 9, and actool rejects the whole catalog if it is present.
"""

import json
import os
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit('Pillow is required: pip install Pillow')

SOURCE = 'arbigram/icon/source-1024.png'
TARGET = 'Telegram/Telegram-iOS/AppIcons.xcassets/ArbigramIcon.appiconset'

# (idiom, size string, scale, pixels)
SLOTS = [
    ('iphone', '20x20', '2x', 40),
    ('iphone', '20x20', '3x', 60),
    ('iphone', '29x29', '2x', 58),
    ('iphone', '29x29', '3x', 87),
    ('iphone', '40x40', '2x', 80),
    ('iphone', '40x40', '3x', 120),
    ('iphone', '60x60', '2x', 120),
    ('iphone', '60x60', '3x', 180),
    ('ipad', '20x20', '2x', 40),
    ('ipad', '29x29', '2x', 58),
    ('ipad', '40x40', '2x', 80),
    ('ipad', '76x76', '2x', 152),
    ('ipad', '83.5x83.5', '2x', 167),
    ('ios-marketing', '1024x1024', '1x', 1024),
]


def main():
    if not os.path.exists(SOURCE):
        sys.exit('missing source image: %s' % SOURCE)

    base = Image.open(SOURCE).convert('RGB')
    if base.size != (1024, 1024):
        base = base.resize((1024, 1024), Image.LANCZOS)

    os.makedirs(TARGET, exist_ok=True)
    for name in os.listdir(TARGET):
        os.remove(os.path.join(TARGET, name))

    images, rendered = [], {}
    for idiom, size, scale, px in SLOTS:
        filename = 'Arbigram-%d.png' % px
        if px not in rendered:
            base.resize((px, px), Image.LANCZOS).save(os.path.join(TARGET, filename))
            rendered[px] = filename
        images.append({
            'size': size,
            'idiom': idiom,
            'filename': filename,
            'scale': scale,
        })

    manifest = {'images': images, 'info': {'version': 1, 'author': 'xcode'}}
    with open(os.path.join(TARGET, 'Contents.json'), 'w', encoding='utf-8') as f:
        json.dump(manifest, f, indent=2)
        f.write('\n')

    print('%s  ->  %d slots, %d files' % (TARGET, len(images), len(rendered)))
    print('sizes: %s' % ', '.join(str(p) for p in sorted(rendered)))


if __name__ == '__main__':
    main()
