#!/usr/bin/python3

# vim: set expandtab shiftwidth=4 softtabstop=4: 

# Same comments as in get_build_deps.py

import sys
import json

def e(s):
    hell = Exception("Error, e() expects a string or list of strings")
    if isinstance(s, str):
        s = [ s ]
    if not isinstance(s, list):
        raise hell
    for l in s:
        if not isinstance(l, str):
            raise hell
        print(l, file = sys.stderr)
    raise Exception(s[0])

fauxenv = []

def main():
    if len(sys.argv) != 1:
        e([ "Error, wrong number of arguments",
            f"usage: {sys.argv[0]}"])
    fauxenv = json.load(sys.stdin)
    if 'DEPS' not in fauxenv:
        e("Error, no 'DEPS' on stdin")
    deps = fauxenv['DEPS'].split()
    local_files = [ fauxenv[f"{d}_LOCAL_FILE"] for d in deps \
                if f"{d}_LOCAL_FILE" in fauxenv ]
    upstream = [ d for d in deps if f"{d}_LOCAL_FILE" not in fauxenv ]
    local_copy = ""
    local_install = ""
    for f in local_files:
        local_copy += f" {f}"
        local_install += f" /{f}"
    if len(local_copy) > 0:
        print(f"COPY {local_copy} /")
        print(f"RUN apt install -y {local_install} && rm -f {local_install}")
    upstream_install = ""
    for d in upstream:
        upstream_install += f" {d}"
    if len(upstream_install) > 0:
        print(f"RUN apt-get install -y {upstream_install}")

if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        sys.exit(1)
