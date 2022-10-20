import json

# Apparently there's all sorts of "history" around unions with python types.
# I'm implementing the semantics here, without ambiguity. Hopefully this can be
# replaced by something more pythonic, especially once there's something
# working and we have test-cases. Our interest is in a non-shallow merge of
# arbitrary imports from JSON. So we're only interested in supporting python
# data structures that contain primitives, sets, lists, and dicts (or
# subclasses thereof). In fact we needn't support sets for that matter, but
# it's not hard to.
#
# The defined semantics are;
#   - if both fields are isinstance(dict), the output is initially a copy of
#     the left dict, then modified by each key-value pair in the right
#     field/dict;
#      - if the left/output dict does not have the corresponding key, the right
#        dict's key-value pair is simply inserted into the output dict.
#      - otherwise, the value inserted into the output dict for that key is
#        obtained by a recursive call to this union function.
#     Exception: if noDictUnion=True, the right dict is the resulting value.
#   - if both values are lists, the resulting value is the list "+"
#     (concatenation) of the two lists.
#      - Exception: if noListUnion=True, the right list is the resulting value.
#      - if listDedup=True, the resulting list is de-duplicated.
#   - if both values are sets, the resulting value is the set "|" (union) of
#     the two sets. Exception: if noSetUnion=True, the right set is the
#     resulting value.
#   - otherwise the right value is used.

class HcpUnion(Exception):
	pass

# TODO: this should be turned into one of those "class-factory"-like Python
# classes.
def union(a, b, noDictUnion=False, noListUnion=False, noSetUnion=False,
		listDedup=True):
	ta = type(a)
	tb = type(b)
	if ta != tb:
		return b
	if ta == dict and not noDictUnion:
		result = a.copy()
		for i in b:
			if i in a:
				result[i] = union(a[i], b[i], noDictUnion, noListUnion, noSetUnion)
			else:
				result[i] = b[i]
		return result
	if ta == list and not noListUnion:
		c = a + b
		if listDedup:
			d = list()
			for i in c:
				if i not in d:
					d.append(i)
			c = d
		return c
	if ta == set and not noSetUnion:
		return a | b
	return b
