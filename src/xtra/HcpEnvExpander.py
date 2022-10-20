import json

from HcpJsonPath import valid_path_node

class HcpEnvExpanderError(Exception):
	pass

# Given a dict that should serve as an "env", validate it
def env_check(e):
	for i in e:
		valid_path_node(i)
		v = e[i]
		if not isinstance(v, str):
			raise HcpEnvExpanderError(f"HCP JSON, element '{i}' not a string")

# Given a JSON string, decode it into an "env" dict and curate along the way to
# make sure it's valid.
def env_decode(s):
	e = json.loads(s)
	env_check(e)
	return e

# Given an "env" dict, convert it back to a JSON string
def env_encode(e):
	return json.dumps(e)

# Given a string (presumably JSON), perform a single pass of parameter
# expansion on it with a single key-value pair. Specifically, if k is "foo" and
# v is "bar", we want to replace every occurrence of "{foo}" with "bar". (Don't
# be fooled by the tripled braces in the code, that's just dealing with
# f-strings and escapes.)
def env_expand_single(s, k, v):
	return s.replace(f"{{{k}}}", v)

# Given a string (presumably JSON), perform a single pass of parameter
# expansion on it with an "env" dict. Ie. each key-value pair in the "env" is
# used for parameter expansion.
def env_expand(s, e):
	for i in e:
		s = env_expand_single(s, i, e[i])
	return s

# Given an "env" dict, have it perform parameter-expansion on its own string
# (JSON) representation repeatedly until it stops changing or we hit a give-up
# threshold. (Or, if enabled, the string representation exceeds a size
# threshold.)
# Returns a 2-tuple of (a) the final string representation, and (b) the
# corresponding (post-expansion) "env" dict.
# In case you're wondering, we need an escape condition to avoid infinite loops
# if people write dumb (or mischievous) or "env"s.
# E.g. suppose we have;
#   input data = "{foo} {bar}",
#   "env" = {
#       'foo': '{bar}',
#       'bar': '{foo}'
#   }
# Each round of parameter expansion flips the data between two alternating
# forms, so it never stabilizes and an escape condition is required.
# Also you can also build decompression bombs, so using the size threshold may
# be preferable to waiting for a memory limit to kick in;
#   input data = "{foo}",
#   "env" = {
#       'foo': '{foo} {foo} {foo} {foo} {foo} {foo} {foo} {foo} {foo} {foo}'
#   }
# This grows at O(10^n), so memory limits will kick in long before the loop
# limit does. Set maxsize to zero to remove the limit, e.g. if you expect large
# expansions and trust your inputs (or you want the system to decide when
# enough is enough).
def env_selfexpand(e, maxsize = 1000000):
	s = env_encode(e)
	count = 20
	while count > 0:
		count = count - 1
		s = env_expand(s, e)
		if maxsize > 0 and len(s) > maxsize:
			raise HcpEnvExpanderError(
				f"HCP JSON, env decompression bomb?: {len(s)}")
		newe = env_decode(s)
		if (newe == e):
			break;
		e = newe
	return s, e

def loads(s, autoexpand=True):
	e = env_decode(s)
	if not autoexpand:
		return e
	_, e = env_selfexpand(e)
	return e

def load(f, **kwargs):
	s = f.read()
	return loads(s, **kwargs)
