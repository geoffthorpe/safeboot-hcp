#!/usr/bin/python3

# vim: set expandtab shiftwidth=4 softtabstop=4: 

# This is a rare thing, a python script that is expected to run on the host.
# We try to put and run all "things prone to variance" inside containers, so
# that they don't (vary). So the host is mostly limited to GNUmake, bash, and
# docker. In keeping with that spirit, this script intentionally uses and does
# nothing exotic, and in particular it doesn't import any helpers/wrappers.

import os
import sys

def e(s):
    hell = Exception("e() expects a string or list of strings")
    if isinstance(s, str):
        s = [ s ]
    if not isinstance(s, list):
        raise hell
    for l in s:
        if not isinstance(l, str):
            raise hell
        print(l, file = sys.stderr)
    raise Exception(s[0])

def main():
    if len(sys.argv) != 3:
        e([ "Error wrong number of arguments",
            f"usage: {sys.argv[0]} <path-to-source> <exclusions>"])

    srcdir = sys.argv[1]
    debcontrol = f"{srcdir}/debian/control"
    exclusions = sys.argv[2].split(' ')

    if not os.path.isdir(srcdir):
        e(f"Package source directory missing: {srcdir}")
    if not os.path.isfile(debcontrol):
        e(f"Debian control file missing: {debcontrol}")

    alldeps = []
    with open(debcontrol, 'r') as f:
        processing = False
        while not processing:
            l = f.readline()
            if len(l) == 0:
                e("No 'Build-Depends': {debcontrol}")
            l = l.strip()
            if not l.startswith('Build-Depends:'):
                continue
            l = l[len('Build-Depends:'):].strip()
            processing = True
        while processing:
            deps = l.split(',')
            numdeps = len(deps)
            # If the line finished with a ',', the last item in 'deps' will
            # be the empty string, which is also our indicator as to
            # whether this is our last line of dependencies, or whether
            # we'll keep "processing"...
            processing = deps[numdeps - 1] == ''
            if processing:
                deps.pop(numdeps - 1)
            # For each dep, remove anything including and following a space or
            # an open bracket.
            for d in deps:
                d = d.strip()
                i = d.find(' ')
                if i >= 0:
                    d = d[0:i]
                i = d.find('(')
                if i >= 0:
                    d = d[0:i]
                if d not in exclusions:
                    alldeps += [ d ]
            if processing:
                l = f.readline()
                if len(l) == 0:
                    e("Unterminated 'Build-Depends': {debcontrol}")
                l = l.strip()
    print(' '.join(alldeps))

if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        sys.exit(1)
