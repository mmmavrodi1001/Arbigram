#!/usr/bin/env python3
"""
Arbigram — build the over-the-air install page.

iOS installs an already-signed app straight from Safari when it is handed an
itms-services:// link pointing at a manifest. The manifest has to sit on HTTPS
and name the exact bundle id and version of the package it describes, so all of
that is read back out of the built IPA rather than repeated by hand.

  python3 arbigram/make-site.py \\
      --ipa build/artifacts/Arbigram-12.9.2-30751.ipa \\
      --base-url https://user.github.io/Arbigram \\
      --ipa-url https://github.com/user/Arbigram/releases/download/b30751/Arbigram-12.9.2-30751.ipa \\
      --out site
"""

import argparse
import io
import os
import plistlib
import re
import shutil
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))


def read_ipa(path):
    """Pull the fields the manifest has to agree with out of the package."""
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        info = [n for n in names if re.match(r'^Payload/[^/]+/Info\.plist$', n)]
        if not info:
            sys.exit('no Info.plist inside %s' % path)
        p = plistlib.loads(z.read(info[0]))
    return {
        'bundle_id': p['CFBundleIdentifier'],
        'title': p.get('CFBundleDisplayName') or p['CFBundleName'],
        'version': p['CFBundleShortVersionString'],
        'build': p['CFBundleVersion'],
    }


def write_manifest(out, app, ipa_url, base_url):
    manifest = {
        'items': [{
            'assets': [
                {'kind': 'software-package', 'url': ipa_url},
                {'kind': 'display-image', 'url': base_url + '/icon-57.png'},
                {'kind': 'full-size-image', 'url': base_url + '/icon-512.png'},
            ],
            'metadata': {
                'bundle-identifier': app['bundle_id'],
                'bundle-version': app['build'],
                'kind': 'software',
                'title': app['title'],
            },
        }],
    }
    with open(os.path.join(out, 'manifest.plist'), 'wb') as f:
        plistlib.dump(manifest, f)


def write_index(out, app, ipa_url, base_url, size_mb):
    template = io.open(os.path.join(HERE, 'site', 'index.html'), encoding='utf-8').read()
    install_url = 'itms-services://?action=download-manifest&amp;url=%s/manifest.plist' % base_url
    filled = (template
              .replace('__TITLE__', app['title'])
              .replace('__VERSION__', app['version'])
              .replace('__BUILD__', app['build'])
              .replace('__BUNDLE_ID__', app['bundle_id'])
              .replace('__SIZE__', '%.0f' % size_mb)
              .replace('__INSTALL_URL__', install_url)
              .replace('__IPA_URL__', ipa_url))
    io.open(os.path.join(out, 'index.html'), 'w', encoding='utf-8', newline='\n').write(filled)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--ipa', required=True)
    ap.add_argument('--base-url', required=True, help='https root the page is served from, no trailing slash')
    ap.add_argument('--ipa-url', required=True, help='https url the package itself is downloaded from')
    ap.add_argument('--out', default='site')
    args = ap.parse_args()

    base_url = args.base_url.rstrip('/')
    app = read_ipa(args.ipa)
    size_mb = os.path.getsize(args.ipa) / (1024.0 * 1024.0)

    os.makedirs(args.out, exist_ok=True)
    for icon in ('icon-57.png', 'icon-512.png'):
        shutil.copyfile(os.path.join(HERE, 'site', icon), os.path.join(args.out, icon))

    write_manifest(args.out, app, args.ipa_url, base_url)
    write_index(args.out, app, args.ipa_url, base_url, size_mb)

    # A .nojekyll keeps Pages from running the files through Jekyll, which would
    # otherwise be free to reinterpret anything starting with an underscore.
    io.open(os.path.join(args.out, '.nojekyll'), 'w').write('')

    print('%s  ->  %s %s (%s), %.0f MB' % (args.out, app['title'], app['version'], app['build'], size_mb))
    print('manifest: %s/manifest.plist' % base_url)
    print('package:  %s' % args.ipa_url)


if __name__ == '__main__':
    main()
