#!/usr/bin/python3

# vim: set expandtab shiftwidth=4 softtabstop=4: 

import os
import sys
import json

# Give internally-generated exceptions a type so that our top-level exception
# handler can be prettier. (Any other exceptions get all the python noise
# they're entitled to.)
class myException(Exception):
    pass

def e(s, iserr = True):
    hell = Exception("e() expects a string or list of strings")
    if isinstance(s, str):
        s = [ s ]
    if not isinstance(s, list):
        raise hell
    for l in s:
        if not isinstance(l, str):
            raise hell
        print(l, file = sys.stderr)
    if iserr:
        raise myException(s[0])
    sys.exit(0)

origcmd = sys.argv[0]

def usage(errmsg = None, **kwargs):
    if not errmsg:
        errmsg = []
    errmsg += [
        f"    usage: {origcmd} [options]",
        "A JSON representation of the debian control file is read from",
        "stdin and a makefile stub (for inclusion) is produced containing",
        "the relevant variables.",
        "Options:",
        "  -i <input>, read JSON input from a file rather than stdin.",
        "  -o <output>, write makefile stub to a file rather than stdout."
    ]
    e(errmsg, **kwargs)

# The JSON encoding has every attribute as a list. Many of those attributes are
# supposed to be a single value, so this function checks and returns that.
def get_single_val(thestruct, propname):
    if propname not in thestruct:
        e(f"No '{propname}' attribute")
    propval = thestruct[propname]
    if not isinstance(propval, list):
        e(f"The '{propname}' attribute is not list-typed")
    if len(propval) != 1:
        e(f"The '{propname}' list has {len(propval)} entries, not 1")
    return propval[0]

def main():
    infile = None
    outfile = None

    # Pop the executable off the argv list so we're left with cmd-line arguments
    sys.argv.pop(0)
    while len(sys.argv) > 0:
        if len(sys.argv) == 1:
            usage(['Uneven argument list'])
        optkey = sys.argv.pop(0)
        optval = sys.argv.pop(0)
        if optkey == '-i':
            if infile:
                usage(["'-i' provided more than once"])
            infile = open(optval, 'r')
        elif optkey == '-o':
            if outfile:
                usage(["'-o' provided more than once"])
            outfile = open(optval, 'w')
        else:
            usage([f"Unrecognized option: {optkey} {optval}"])
    if infile:
        sys.stdin = infile
    if outfile:
        sys.stdout = outfile

    result = json.load(sys.stdin)

    pkgset = get_single_val(result, 'Source')
    print(f"# Package set: {pkgset}")
    print(f"$(eval {pkgset}_PKGS :=)")
    builddeps = []
    if 'Build-Depends' in result:
        builddeps = result['Build-Depends']
    print(f"$(eval {pkgset}_PKG_BUILD_DEPENDS := {' '.join(builddeps)})")
    for p in result['Package']:
        pkgname = get_single_val(p, 'Package')
        print(f"# Individual package: {pkgset} :: {pkgname}")
        print(f"$(eval {pkgset}_PKGS += {pkgname})")
        pkgdeps = []
        if 'Depends' in p:
            pkgdeps = p['Depends']
        pkgdeps = [d for d in pkgdeps if d.find('$') == -1]
        print(f"$(eval {pkgname}_DEPENDS := {' '.join(pkgdeps)})")

if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        if isinstance(e, myException):
            sys.exit(1)
        raise e
