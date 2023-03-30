#!/usr/bin/python3

# vim: set expandtab shiftwidth=4 softtabstop=4: 

import os
import sys
import re
import json

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

# Parses the next attribute, and returns it as a 2-tuple (attr-name,value_list).
# 'attr-name' will be None if EOF is encountered.
# Note, multi-line text attributes will be horrifically mistreated. The parsing
# assumes that all attribute values are comma-separated lists. Also, parsing
# only continues to the next line if the last character is a comma. Both of
# those assumptions are false for multi-line text. Also, each comma-delimited
# item will crop off any open bracket '(' character and all that follows it.
# This util really only exists (for now) to extract package filename and
# dependency information.
attr_regex = re.compile('^[A-Z][A-Za-z-]*:')
bracket_regex = re.compile('\(.*\)')
def next_attribute(fp):
    while True:
        l = fp.readline()
        if len(l) == 0:
            return (None, None)
        l = l.strip()
        s = attr_regex.search(l)
        if s:
            break
    attr_name = l[0 : s.span(0)[1] - 1]
    l = l[s.span()[1] : ].strip()
    allvals = []
    while True:
        if len(l) == 0:
            break
        vals = l.split(',')
        numvals = len(vals)
        # If the line finished with a ',', the last item in 'vals' will
        # be the empty string, which is also our indicator as to
        # whether this is our last line of dependencies, or whether
        # we'll keep "processing"...
        processing = vals[numvals - 1] == ''
        if processing:
            vals.pop(numvals - 1)
        # For each dep, remove any bracketed text and anything following it
        for d in vals:
            d = d.strip()
            m = bracket_regex.search(d)
            if m:
                d = d[:m.span(0)[0]].strip()
            allvals += [ d ]
        if not processing:
            break
        l = fp.readline()
        if len(l) == 0:
            e(f"Unterminated '{attr_name}' in debian control file")
        l = l.strip()
    return attr_name, allvals

def parse_control(srcdir, debiandir = None):
    if debiandir:
        debcontrol = f"{debiandir}/control"
    else:
        debcontrol = f"{srcdir}/debian/control"
    if not os.path.isfile(debcontrol):
        e(f"Debian control file missing: {debcontrol}")
    # The basic idea is; we continue pulling attributes and putting
    # them at the 'current' location within the 'result' structure,
    # unless that attribute is 'Package', in which case a new dict
    # entry is created in the result['Package'] list, the 'current'
    # location is repointed to that new entry, and the 'Package'
    # attribute is set in that new entry.
    result = {
        'srcdir': srcdir,
        'Package': []
    }
    if debiandir:
        result['debiandir'] = debiandir
    current = result
    with open(debcontrol, 'r') as f:
        while True:
            attr_name, attr_vals = next_attribute(f)
            if attr_name == None:
                break
            if attr_name == 'Package':
                newpkg = {}
                result['Package'].append(newpkg)
                current = newpkg
            current[attr_name] = attr_vals
    return result

def main():
    if len(sys.argv) < 2 or len(sys.argv) > 3:
        e([ "Error wrong number of arguments",
            f"    usage: {sys.argv[0]} <srcdir> [debiandir]",
            "The debian 'control' file is parsed, and the result is written to",
	    "stdout as a JSON object.",
            "If [debiandir] is provided, then the control file is assumed read",
            "from '<debiandir>/control', otherwise it is read from",
            "'<srcdir>/debian/control'." ])
    srcdir = sys.argv[1]
    debiandir = None
    if len(sys.argv) == 3:
        debiandir = sys.argv[2]
    result = parse_control(srcdir, debiandir = debiandir)
    print(json.dumps(result))

if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        print(f"Failure: {e}")
        sys.exit(1)
