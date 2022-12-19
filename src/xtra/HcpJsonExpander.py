#  vim: set expandtab shiftwidth=4 softtabstop=4:  #
import json
import HcpJsonPath

default_varskey = 'vars'
default_fileskey = 'files'
default_retainkeys = True

class HcpJsonExpanderError(Exception):
    pass

# vars_merge_vars() and vars_merge_files() need to return a new context, so
# that the input is unaffected. This is what will allow recursion to "work",
# ie. we get environment specialization as we descend an objection hierarchy,
# but we drop those specializations as we come back up the hierarchy and go
# down other branches.
def vars_merge_vars(ctxvars1, ctxvars2):
    newctx = ctxvars1.copy()
    for k in ctxvars2:
        newctx[k] = ctxvars2[k]
    return newctx

def vars_merge_files(ctxvars, ctxfiles, currentpath):
    newctx = ctxvars.copy()
    for k in ctxfiles:
        v = ctxfiles[k]
        if isinstance(v, str):
            with open(v, 'r') as fp:
                newv = json.load(fp)
        elif isinstance(v, dict):
            if 'source' not in v or 'path' not in v:
                es = f"files dict at {currentpath}.{k} is malformed"
                raise HcpJsonExpanderError(es)
            with open(v['source'], 'r') as fp:
                newv = json.load(fp)
            newv = HcpJsonPath.extract_path(newv, v['path'], must_exist = True)
        else:
            es = f"files entry at {currentpath}.{k} is malformed"
            raise HcpJsonExpanderError(es)
        # This can fail if k conflicts with an existing key.
        try:
            newctx[k] = newv
        except Exception as e:
            es = f"failed substitution, path={currentpath}, key={k}: {e}"
            raise HcpJsonExpanderError(es)
    return newctx

# This uses a vars struct to transform a single string and return the result.
# The curious thing here is that we handle string-valued vars differently from
# non-string-valued ones. For all string-valued vars (eg. "key": "value"), we
# replace any substrings of the form "{key}" with "value". For any
# non-string-valued vars (eg. "key": [ 0, "whatever", null ]), we only
# intervene if the _entire_ string is "{key}", in which case we return
# immediately with the (non-string-valued) value.
def vars_expandstring(ctxvars, s):
    for k in ctxvars:
        v = ctxvars[k]
        if isinstance(v, str):
            s = s.replace(f"{{{k}}}", v)
        else:
            if s == f"{{{k}}}":
                return v
    return s

# See https://www.w3schools.com/js/js_json_datatypes.asp
def vars_expand(ctxvars, obj, currentpath):
    if isinstance(obj, str):
        return vars_expandstring(ctxvars, obj)
    if isinstance(obj, int):
        return obj
    if isinstance(obj, dict):
        # The expansion should not modify and return 'obj', rather it should
        # modify a copy and return that.
        newobj = {}
        for k in obj:
            v = obj[k]
            newk = vars_expandstring(ctxvars, k)
            if currentpath == '.':
                newpath = f".{newk}"
            else:
                newpath = f"{currentpath}.{newk}"
            newv = vars_expand(ctxvars, v, newpath)
            # This can fail if newk somehow ended up not being a string or if
            # it now conflicts with an existing key (eg. if expansion caused
            # different keys to become the same).
            try:
                newobj[newk] = newv
            except Exception as e:
                es = f"failed substitution, path={currentpath}, key={newk}: {e}"
                raise HcpJsonExpanderError(es)
        return newobj
    if isinstance(obj, list):
        newobj = []
        for k in obj:
            newpath = f"{currentpath}[]"
            newk = vars_expand(ctxvars, k, newpath)
            newobj.append(newk)
        return newobj
    if isinstance(obj, bool):
        return obj
    if obj == None:
        return obj
    es = f"unrecognised element type, path={currentpath}, type={type(obj)}"
    raise HcpJsonExpanderError(es)

def vars_fullexpand(ctxvars, obj, currentpath):
    escape = 10
    while escape > 0:
        newobj = vars_expand(ctxvars, obj, currentpath)
        if newobj == obj:
            break
        obj = newobj
        escape -= 1
    return newobj 

def vars_selfexpand(ctxvars, currentpath):
    return vars_fullexpand(ctxvars, ctxvars, currentpath)

# This function is almost a duplicate of vars_expand(), which does variable
# expansion through an object, but in out case we're accumulating vars/files
# sections as we descend into the structure, whereas vars_expand() doesn't.
def process_obj(ctxvars, obj, currentpath = '.',
            varskey = default_varskey, fileskey = default_fileskey,
            retainkeys = default_retainkeys):
    if isinstance(obj, dict):
        obj = obj.copy()
        # First, if we have a vars section, extract it, merge it with the vars
        # we already had, and self-expand to completion. Actually, the
        # self-expansion is done unconditionally, just in case we were passed
        # in a 'ctxvars' that hadn't yet been self-expanded (in which case, we
        # want it self-expanded whether or not we have local vars to add to the
        # mix).
        origvars = None
        if varskey in obj:
            origvars = obj.pop(varskey)
            if not isinstance(origvars, dict):
                es = f"vars structure ('{varskey}') not a dict: {currentpath}"
                raise HcpJsonExpanderError(es)
            ctxvars = vars_merge_vars(ctxvars, origvars)
        ctxvars = vars_selfexpand(ctxvars, currentpath)
        # Next, if we have a files section, extract it, expand it using our
        # vars, then load the specified files into vars, then self-expand vars
        # to completion (again).
        origfiles = None
        if fileskey in obj:
            origfiles = obj.pop(fileskey)
            if not isinstance(origfiles, dict):
                es = f"files structure ('{fileskey}') not a dict: {currentpath}"
                raise HcpJsonExpanderError(es)
            if currentpath == '.':
                newpath = f".{fileskey}"
            else:
                newpath = f"{currentpath}.{fileskey}"
            myfiles = vars_fullexpand(ctxvars, origfiles, newpath)
            ctxvars = vars_merge_files(ctxvars, myfiles, newpath)
            ctxvars = vars_selfexpand(ctxvars, currentpath)
        # Now do the recursion dance for the 'dict' case.
        newobj = {}
        for k in obj:
            v = obj[k]
            newk = vars_expandstring(ctxvars, k)
            if currentpath == '.':
                newpath = f".{newk}"
            else:
                newpath = f"{currentpath}.{newk}"
            newv = process_obj(ctxvars, v, newpath,
                        varskey = varskey, fileskey = fileskey)
            # This can fail if newk somehow ended up not being a string or if
            # it now conflicts with an existing key (eg. if expansion caused
            # different keys to become the same).
            try:
                newobj[newk] = newv
            except Exception as e:
                es = f"failed substitution, path={newpath}, key={newk}: {e}"
                raise HcpJsonExpanderError(es)
        if retainkeys:
            if origvars:
                newobj[varskey] = origvars
            if origfiles:
                newobj[fileskey] = origfiles
        return newobj
    if isinstance(obj, list):
        newobj = []
        for v in obj:
            newpath = f"{currentpath}[]"
            newv = process_obj(ctxvars, v, newpath,
                        varskey = varskey, fileskey = fileskey)
            newobj.append(newv)
        return newobj
    # 'obj' is a primitive type (no recursion), vars_expand() will handle that.
    # There's only one catch ...
    newobj = vars_expand(ctxvars, obj, currentpath)
    # ... what if the newobj we get back is _not_ a primitive type? Eg. what if
    # 'obj' is the string value of a dict element and it happens to be
    # '{SOMEFILE}', and our SOMEFILE is already mapped to a JSON object in
    # ctxvars (from a previous "files" inclusion) - in this case, the expansion
    # will returning that object rather than a string.
    #
    # Why does that matter? I'm glad you asked.
    #
    # The problem: if the 'obj' passed into this function had been that object
    # all along (rather than first being a string that got _substituted_ by an
    # object), the dict/list-handling above would have recursed into it,
    # processed any vars/files, etc. But as it stands, we came into this
    # function with type(obj)==str and need to explicitly catch this pivot in
    # the object type, and reprocess it if need be.
    if isinstance(obj, str) and type(newobj) != str:
            # Recurse to re-process with the substituted value
            newobj = process_obj(ctxvars, newobj, currentpath,
                        varskey = varskey, fileskey = fileskey)
    return newobj

def _load(obj, varskey = default_varskey, fileskey = default_fileskey,
            retainkeys = default_retainkeys):
    ctxvars = {}
    ctxfiles = {}
    currentpath = '.'
    return process_obj(ctxvars, obj, currentpath = currentpath,
                varskey = varskey, fileskey = fileskey,
                retainkeys = retainkeys)

def loads(s, varskey = default_varskey, fileskey = default_fileskey,
            retainkeys = default_retainkeys):
    obj = json.loads(s)
    return _load(obj, varskey = varskey, fileskey = fileskey,
                retainkeys = retainkeys)

def load(fp, varskey = default_varskey, fileskey = default_fileskey,
            retainkeys = default_retainkeys):
    obj = json.load(fp)
    return _load(obj, varskey = varskey, fileskey = fileskey,
                retainkeys = retainkeys)

def test():
    with open('input.json', 'r') as fp:
        foo = load(fp)
    return foo
