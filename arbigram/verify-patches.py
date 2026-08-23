#!/usr/bin/env python3
"""
Arbigram — check that apply-patches.py still reproduces the fork.

apply-patches.py is the fork's only way back after an upstream merge: it
reconstructs every edit made to an upstream file. That makes it worth exactly
as much as its accuracy, and nothing warns you when it drifts — a hand edit
made straight in the working tree leaves the patch set a version behind, and
you find out during a merge, months later, with no way to tell which half was
right.

So: rebuild every patched file from the pristine upstream commit the fork is
based on, and compare the result byte for byte against what is committed. Any
difference is either a patch that was never written or a patch that has gone
stale, and both are worth failing a build over.

Run from the repository root:  python3 arbigram/verify-patches.py
"""

import io
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
APPLY = os.path.join(HERE, 'apply-patches.py')
BASE_FILE = os.path.join(HERE, 'upstream-base.txt')

def patched_paths(work):
    """Every file apply-patches.py writes to, discovered by asking it.

    Reading the paths out of the source looked simpler and was wrong twice: a
    quoted-path regex missed the two patches against .gitmodules, and a syntax
    tree missed the ones whose path is a loop variable. So run the patch set
    against an empty directory instead — every patch then fails with the path it
    wanted, which is the list, straight from the code that owns it.
    """
    applied = subprocess.run(
        [sys.executable, APPLY], cwd=work,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    output = applied.stdout.decode('utf-8', 'replace')
    return sorted(set(re.findall(r'file not found: (\S+)', output)))


def git(*args, **kwargs):
    return subprocess.run(
        ['git', '-C', REPO] + list(args),
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)


def main():
    base = io.open(BASE_FILE, encoding='utf-8').read().strip()

    if git('cat-file', '-e', base + '^{commit}').returncode != 0:
        # A shallow clone has the branch tip and nothing else. Ask for the one
        # commit rather than the whole of upstream's history.
        print('fetching upstream base %s' % base[:12])
        if git('fetch', '--depth=1', 'origin', base).returncode != 0:
            git('fetch', 'origin', 'master:refs/remotes/origin/master')
        if git('cat-file', '-e', base + '^{commit}').returncode != 0:
            print('FAIL: upstream base %s is not in this clone' % base)
            return 1

    empty = tempfile.mkdtemp(prefix='arbigram-paths-')
    try:
        paths = patched_paths(empty)
    finally:
        shutil.rmtree(empty, ignore_errors=True)
    if not paths:
        print('FAIL: no patched paths found in apply-patches.py')
        return 1

    work = tempfile.mkdtemp(prefix='arbigram-verify-')
    try:
        # Only the files the patch set names, taken straight out of the base
        # commit. Checking out all thirty thousand would cost a minute for
        # nothing.
        missing = []
        for path in paths:
            result = git('show', '%s:%s' % (base, path))
            if result.returncode != 0:
                missing.append(path)
                continue
            destination = os.path.join(work, path)
            os.makedirs(os.path.dirname(destination), exist_ok=True)
            with open(destination, 'wb') as f:
                f.write(result.stdout)

        if missing:
            print('FAIL: not present in the upstream base:')
            for path in missing:
                print('  %s' % path)
            return 1

        applied = subprocess.run(
            [sys.executable, APPLY], cwd=work,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        output = applied.stdout.decode('utf-8', 'replace')
        if applied.returncode != 0:
            print(output)
            print('FAIL: apply-patches.py did not apply cleanly')
            return 1

        summary = output.strip().split('\n')[-1]

        differing = []
        for path in paths:
            rebuilt = os.path.join(work, path)
            committed = os.path.join(REPO, path)
            with open(rebuilt, 'rb') as f:
                a = f.read()
            with open(committed, 'rb') as f:
                b = f.read()
            if a != b:
                differing.append(path)

        print('%s, %d files compared' % (summary, len(paths)))
        if differing:
            print('')
            print('FAIL: the patch set no longer reproduces these files:')
            for path in differing:
                print('  %s' % path)
            print('')
            print('Either an edit was made without adding its patch, or a patch')
            print('is a version behind the file. Fix apply-patches.py, then run')
            print('this again.')
            return 1

        print('the patch set reproduces the fork exactly')
        return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main())
