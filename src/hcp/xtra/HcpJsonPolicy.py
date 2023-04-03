# This 'policy' abstraction implements a filtering scheme for JSON objects, and
# a JSON layout for configuring it that works a little like iptables, with the
# concept of filter rules, and chains thereof. (The terms 'rule' and 'filter'
# are used interchangeably.)
#
# 'Policy' layout (ie. the top-level of 'policy.json');
#
#   {
#     "start": <string matching a key in "filters">
#         This names the top-level rule to "call" to perform filtering.
#     "default": <"accept", or "reject" (the default)>
#         The action to take if the control ever returns from the call.
#     "filters": <struct of key-value pairs>
#         Each key names a filter entry, and the corresponding value is a
#         struct providing the details of that filter entry (see layout below).
#         Note that this JSON file undergoes processing that can transform
#         these filters. (See "chains".)
#   }
#
# 'Filter entry' layout (ie. values in the 'filters' struct);
#
#   "filtername1": {
#     "name": <string>
#         Optional. If defined, will replace "filtername1" as the key/name of
#         filter in the top-level "filters" struct. (Yes this _is_ a useful
#         trick, in case you thought it pointless, though you"ll have to
#         read further to find out how that might be. See "chains".)
#
#     "action": <"accept", "reject", "jump", "call", "return", or "next">
#         The action associated with this rule. It will be performed if the
#         rule has no conditional ("if") or the conditional evaluates true.
#         If set to "call" or "jump", then the "call" or "jump" fields
#         (respectively) must name the filter entry to pass control to.
#
#     "jump": <string naming the rule to pass control to>
#         Only required if action==jump, as described for "action".
#
#     "call": <string naming the rule to pass control to>
#         Only required if action==call, as described for "action". Note that
#         it may or may not return, depending on the rules and the data being
#         filtered. If it _does_ return, then "on-return" can specify a
#         subsequent (but less-flexible) action to perform when control returns
#         from the call, otherwise the "next" semantic is assumed. Note also
#         that if "scope" is specified, it indicates a jq-style path into the
#         data that the called filter(s) should see (instead of the original
#         data).
#
#     "on-return": <"accept", "reject", "return", or "next" (the default)>
#         Optional. Not used unless action==call and control returns from the
#         call.
#
#     "scope": <string or list>
#         Optional. Not used unless action==call. If provided, the called
#         filter(s) will act on a modified data structure (according to the
#         recipe specified in the "scope" attribute) - if and when control
#         returns from the call, processing continues on the original data
#         structure, ie. the modified data structure only exists for the
#         "scope" of the call. See "scope" section below for details on how
#         this field is constructed.
#
#     "next": <string naming the rule to pass control to>
#         Only required if action==next (which is probably a silly thing to do)
#         or if the rule has a conditional that sometimes evaluates false
#         (which is less silly). This field can be supplied explicitly, but it
#         is usually filled in by post-processing. Read on to find out when and
#         why. (See "chains".)
#
#     "if": <struct containing a condition, or array of such structs>
#         Optional. Specifies a condition which must be true for the rule"s
#         "action" to be performed. (If the condition evaluates false, the
#         "otherwise" action will be taken, if defined, otherwise the "next"
#         semantic is assumed.) Note, if an array of conditions is provided,
#         they are evaluated as a logical-AND ("&&") sequence.
#   }
#
# 'Conditional' layout (ie. value of the 'if' struct in filter entries);
#
#   A conditional can be one of the following types (more to come);
#     'exist', 'not-exist':
#       - these use a jq-style path into the JSON data and the conditional
#         evaluates true iff the data being filtered does or does not
#         (respectively) contain a field at the specified path. Eg.
#         "if": {
#             "exist": ".request.lookup.source"
#         }
#         "if": {
#             "not-exist": ".peer.authenticated"
#         }
#     'equal', 'not-equal':
#       - these also use a jq-style path into the JSON data, but supplement it
#         with a 'value', so that 'equality' depends not only on the path
#         existing in the filtered data, but also that its value be an exact
#         match with the one specified in the conditional. The 'value' may be
#         any valid JSON type ('null', numerals, strings, lists, sets) and
#         equality assumes that the types match (obviously). Eg.
#         "if": {
#             "not-equal": ".request.user",
#             "value": "root"
#         }
#         "if": {
#             "equal": ".",
#             "value": {
#                 "field1": "in this example, we exact-match the entire input",
#                 "field2": null,
#                 "field3": [ "a", "list" ],
#                 "field4": {
#                     "a": "struct"
#                 }
#             }
#         }
#     'subset', 'not-subset':
#       - these are similar to 'equal/not-equal' in that they use jq-style
#         paths to identify what field of the data to compare, and a 'value'
#         attribute to compare it against. The 'subset' comparison is true if
#         and only if; (a) both the 'value' attribute and the path-identified
#         data field are of type 'array', and (b) any and all elements of the
#         data field are contained within the 'value' attribute.
#     'elementof', 'not-elementof':
#       - these are similar to 'subset/not-subset' except that the 'elementof'
#         comparison is checking if the path-identified data field is an
#         element of the 'value' array (rather than a subset of it). As such,
#         the path-identified data field doesn't have to be of type 'array',
#         but it must be (obviously) the same type as whatever element of the
#         'value' array it matches against.
#     'contains', 'not-contains':
#       - the 'contains' comparison is true if and only if the given path is
#         for a data field that is (a) of 'array' type, and (b) contains the
#         'value' attribute as one of its elements.
#     'isinstance', 'not-isinstance':
#       - uses the python operator of the same name to return true if and only
#         if the given path is for a data field that is of the type given by
#         the 'type' attribute. Note, 'type' must be one of the following
#         strings, which provide for JSON and python equivalent terms (and adds
#         synthetic types for None/null);
#             None, null,
#             str, string,
#             int, number,
#             dict, object,
#             list, array,
#             bool, boolean
#
# 'Chains'
#
# In the event that a rule does not terminate processing ('accept' or
# 'reject'), explicitly pass control to another rule ('jump' or 'call'), or
# implicitly return control from a call ('return'), then control passes to the
# 'next' rule. If no 'next' rule exists, a 'reject' action is taken and the
# 'reason' field is filled in to indicate a bug in the policy file!  Observe
# that the top-level 'filters' field provides all of the filter entries indexed
# by name, so there is no implied order to them. Rather than chaining filter
# entries together by explicitly providing "next" fields (which would be
# horrible), the policy allows a special form of filter entry that define a
# chain of filter entries.
#
# If an entry in 'filters' is a list/array type (rather than a struct) the
# post-processor will assume that it contains an ordered sequence of filter
# entries within it. The following example shows how the entries get
# transformed;
#   Before post-processing;
#       "filters": {
#           "regular1": { "action": "reject", "if": { ... } ... },
#           "chain1": [
#               { "action": "reject", "if": { ... } ... },
#               { "action": "accept", "if": { ... } ... },
#               { "name": "foo1", "action": "accept", "if": { ... } ... },
#               { "action": "reject" },
#           ]
#       }
#  After post-processing;
#       "filters": {
#           "regular1": { "action": "reject", "if": { ... } ... },
#           "chain1":   { "action": "reject", "if": { ... } ..., "next": "chain1_1" },
#           "chain1_0": { "action": "reject", "if": { ... } ..., "next": "chain1_1" },
#           "chain1_1": { "action": "accept", "if": { ... } ..., "next": "foo" },
#           "foo":      { "action": "accept", "if": { ... } ..., "next": "chain1_3" },
#           "chain1_3": { "action": "reject" },
#       }
# - if an entry in a chain declares a 'name' field, that becomes the name of
#   the filter entry after expansion, otherwise each entry in the chain gets a
#   suffixed name based on the chain name.
# - all entries in a chain _except the last one_(!) automatically get a 'next'
#   field set, thus creating order. (If the entry already specified a 'next'
#   field that will take precedence.)
#
# 'Scopes'
#
# When a filter entry's "call" action gets triggered, control not only shifts
# to the named filter, but a new "scope" will be entered that lasts up until a
# corresponding "return" action, if at all. This is what distinguishes "call"
# from "jump". (There may be multiple levels of "scope", if there are "calls
# within calls", with the expected stack-like behavior. Ie. each call pushes a
# new scope onto the top of the stack, and each return discards the top-most
# scope and returns to the one underneath it.) Apart from the control-flow
# functionality of the "call" (and "return") mechanism, there is also a
# data-treatment capability built into it, which is where the "scope" attribute
# comes in.
#
# By default, if no "scope" attribute is specified, the data structure being
# acted on by the called filter(s) is the same as the one prior to the call
# (and after the return). However, specifying a "scope" attribute allows a new
# data structure to be crafted from the existing one, that will replace the
# original data structure in filter processing for the duration of the
# call(/return) scope. The syntax of the "scope" attribute takes two forms,
# depending on whether it is specified as a string or list/array. We will
# describe the latter first, as it is more general, then we will describe the
# former as a degenerate case.
#
# The general form of "scope" consists of a array (list) of objects (dicts),
# each of which contribute step-wise in constructing the new data structure,
# which starts out as a new/empty JSON object (dict). Each object in the array
# will specify exactly one method key ("set", "delete", "import", or "union")
# to build on that JSON object. The value for the method key, whose value is a
# jq-style path, specifies what path within the new object the method is being
# applied to. The "import" method is the only operation that uses the existing
# data structure (the "source" attribute indicates what path in the existing
# data structure should be copied into the new one), the remaining methods all
# act strictly within the new data structure.
#
# The following fictitous example shows the different methods and their
# attributes;
#     "scope": [
#         { "set": ".tmp1", "value": [ 1, 2, { "a": "b" } ] },
#         { "set": ".tmp2", "value": {
#                 "name": "Blank",
#                 "group": "Blank" } },
#         { "import": ".tmp3", "source": ".details" },
#         { "union": ".tmp3.headers", "source1": ".tmp3.headers",
#             "source2": ".tmp2" },
#         { "union": ".value", "source1": ".tmp1", "source2": ".tmp3.value" },
#         { "delete": ".tmp3.do_not_care" },
#         { "union": ".final", "source1": null, "source2": ".tmp3" },
#         { "delete": ".tmp1" },
#         { "delete": ".tmp2" },
#         { "delete": ".tmp3" },
#         { "delete": ".final.value" }
#     ]
# If the original data structure is;
#     {
#         "details": {
#             "care": "something",
#             "do_not_care": "something else",
#             "value": [ 3, 4 ],
#             "headers": {
#                 "userid": 4015,
#                 "name": "Nosferatu"
#             }
#         },
#         "ignore_me": "ok"
#     }
# Then the "scope" example produces this new data structure;
#     {
#         "final": {
#             "care": "something",
#             "headers": {
#                 "userid": 4015,
#                 "name": "Blank",
#                 "group": "Blank"
#             },
#         }
#         "value": [ 1, 2, { "a": "b" }, 3, 4 ]
#     }
#
# The simpler form of "scope", when it is just a string, is equivalent to a
# single "import". Ie.
#     "scope": ".foo"
# is equivalent to;
#     "scope": [ { "import": ".", "source": ".foo" } ]
#
# Specifying no "scope" attribute in a "call" action indicates that the called
# filter(s) will operate on the same data as the caller. This is equivalent to
# specifying;
#     "scope": [ { "import": ".", "source": "." } ]

import json
import os

from HcpJsonPath import valid_path_node, valid_path, path_pop_node, \
		extract_path, overwrite_path, delete_path, HcpJsonPathError
from HcpRecursiveUnion import union
import HcpJsonExpander

class HcpJsonPolicyError(Exception):
	pass

# This is noisy even for autopurged debugging logs. You'll probably only want
# to enable this if you have a unit test that reproduces your problem.
import sys
if 'HCP_POLICYSVC_DEBUG' in os.environ:
	def log(s):
		print(s, file = sys.stderr)
		sys.stderr.flush()
else:
	def log(s):
		pass

# Map of type strings for use in 'isinstance' conditionals
typetable = {
	'None': type(None),
	'str': type('str'),
	'int': type(42),
	'dict': type({}),
	'list': type([]),
	'bool': type(True)
}
# Add aliases for JSON terms
typetable['null'] = typetable['None']
typetable['string'] = typetable['str']
typetable['number'] = typetable['int']
typetable['object'] = typetable['dict']
typetable['array'] = typetable['list']
typetable['boolean'] = typetable['bool']

# Condition-handling for "if" filters. 'condbase' defines the set of
# conditions, that can be evaluated, together with functions to (a) confirm
# that the condition is well-formed, and (b) evaluate the condition against an
# input. The 'is_valid' function raises a HcpJsonPolicyError if the condition
# structure is malformed. The 'run' function returns a boolean to indicate the
# result of the condition operating on the input.
def is_valid_exist(c, x, n):
	log(f"FUNC is_valid_exist starting; {c},{x},{n}")
	if len(c) != 1 or not isinstance(c[n], str):
		raise HcpJsonPolicyError(f"{x}: invalid '{n}' condition")
	try:
		valid_path(c[n])
	except HcpJsonPathError as e:
		raise HcpJsonPolicyError(f"{x}: invalid '{n}' path\n{e}")
def is_valid_equal(c, x, n):
	log(f"FUNC is_valid_equal starting; {c},{x},{n}")
	if len(c) != 2 or not isinstance(c[n], str) or 'value' not in c:
		raise HcpJsonPolicyError(f"{x}: invalid '{n}' condition")
	try:
		valid_path(c[n])
	except HcpJsonPathError as e:
		raise HcpJsonPolicyError(f"{x}: invalid '{n}' path\n{e}")
def is_valid_subset(c, x, n):
	log(f"FUNC is_valid_subset starting; {c},{x},{n}")
	is_valid_equal(c, x, n)
	if not isinstance(c['value'], list):
		raise HcpJsonPolicyError(f"{x}: value for '{n}' must be a list")
def is_valid_elementof(c, x, n):
	log(f"FUNC is_valid_elementof starting; {c},{x},{n}")
	is_valid_subset(c, x, n)
def is_valid_contains(c, x, n):
	log(f"FUNC is_valid_contains starting; {c},{x},{n}")
	is_valid_equal(c, x, n)
def is_valid_isinstance(c, x, n):
	log(f"FUNC is_valid_isinstance starting; {c},{x},{n}")
	if len(c) != 2 or not isinstance(c[n], str) or 'type' not in c or \
				not isinstance(c['type'], str):
		raise HcpJsonPolicyError(f"{x}: invalid '{n}' condition")
	try:
		valid_path(c[n])
	except HcpJsonPathError as e:
		raise HcpJsonPolicyError(f"{x}: invalid '{n}' path\n{e}")
	if c['type'] not in typetable:
		raise HcpJsonPolicyError(f"{x}: unknown 'type' for '{n}'")
def run_exist(c, x, n, data):
	log(f"FUNC run_exist starting; {c},{x},{n}")
	path = c[n]
	ok, _ = extract_path(data, path)
	log(f"FUNC run_exist ending; {ok}")
	return ok
def run_equal(c, x, n, data):
	log(f"FUNC run_equal starting; {c},{x},{n}")
	path = c[n]
	ok, data = extract_path(data, path)
	if not ok:
		return False
	ok = c['value'] == data
	if not ok:
		log(f"{data} not-equal-to {c['value']}")
	log(f"FUNC run_equal ending; {ok}")
	return ok
def run_subset(c, x, n, data):
	log("FUNC run_subset starting; {c},{x},{n}")
	path = c[n]
	ok, data = extract_path(data, path)
	if not ok:
		return False
	if not isinstance(data, list):
		ok = False
	else:
		ok = set(data).issubset(c['value'])
	if not ok:
		log(f"{data} not-subset-of {c['value']}")
	log(f"FUNC run_subset ending; {ok}")
	return ok
def run_elementof(c, x, n, data):
	log("FUNC run_elementof starting; {c},{x},{n}")
	path = c[n]
	ok, data = extract_path(data, path)
	if not ok:
		return False
	ok = data in c['value']
	if not ok:
		log(f"{data} not-element-of {c['value']}")
	log(f"FUNC run_elementof ending; {ok}")
	return ok
def run_contains(c, x, n, data):
	log(f"FUNC run_contains starting; {c},{x},{n}")
	path = c[n]
	ok, data = extract_path(data, path)
	if not ok:
		return False
	if not isinstance(data, list):
		ok = False
	else:
		ok = c['value'] in data
	if not ok:
		log(f"{data} does-not-contain {c['value']}")
	log(f"FUNC run_elementof ending; {ok}")
	return ok
def run_isinstance(c, x, n, data):
	log("FUNC run_isinstance starting; {c},{x},{n}")
	path = c[n]
	ok, data = extract_path(data, path)
	if not ok:
		return False
	ok = typetable[c['type']] == type(data)
	if not ok:
		log(f"{data} not-instance-of {c['type']}")
	log(f"FUNC run_isinstance ending; {ok}")
	return ok
condbase = {
	'exist': { 'is_valid': is_valid_exist, 'run': run_exist },
	'equal': { 'is_valid': is_valid_equal, 'run': run_equal },
	'subset': { 'is_valid': is_valid_subset, 'run': run_subset },
	'elementof': { 'is_valid': is_valid_elementof, 'run': run_elementof },
	'contains': { 'is_valid': is_valid_contains, 'run': run_contains },
	'isinstance': { 'is_valid': is_valid_isinstance, 'run': run_isinstance }
}

# Supplement with negated versions of those base conditions
def invert_run_fn(f):
	return lambda c, x, n, d: not f(c, x, n, d)
condneg = {
	f"not-{k}": {
		'is_valid': v['is_valid'],
		'run': invert_run_fn(v['run'])
	} for (k, v) in condbase.items()
}

conds = { **condbase, **condneg }

# This function burrows into structures looking for any dicts having a key
# equal to '_' and removing them.
def strip_comments(x):
	if isinstance(x, dict):
		if '_' in x:
			x.pop('_')
		for i in x:
			strip_comments(x[i])
	if isinstance(x, tuple) or isinstance(x, set) or isinstance(x, list):
		for i in x:
			strip_comments(i)

# Method-handling for "scope" constructs.
def scope_valid_common(s, x, n):
	if not isinstance(s[n], str):
		raise HcpJsonPolicyError(f"{x}: invalid '{n}' scope")
	try:
		valid_path(s[n])
	except HcpJsonPathError as e:
		raise HcpJsonPolicyError(f"{x}: invalid '{n}' path\n{e}")
def scope_valid_set(s, x, n):
	log(f"FUNC scope_valid_set running; {s},{x},{n}")
	scope_valid_common(s, x, n)
	if len(s) != 2 or 'value' not in s:
		raise HcpJsonPolicyError(f"{x}: '{n}' must have (only) 'value'")
def scope_valid_delete(s, x, n):
	log(f"FUNC scope_valid_delete running; {s},{x},{n}")
	scope_valid_common(s, x, n)
	if len(s) != 1:
		raise HcpJsonPolicyError(f"{x}: '{n}' expects no attributes")
def scope_valid_import(s, x, n):
	log(f"FUNC scope_valid_import running; {s},{x},{n}")
	scope_valid_common(s, x, n)
	if len(s) != 2 or 'source' not in s:
		raise HcpJsonPolicyError(f"{x}: '{n}' must have (only) 'source'")
	try:
		valid_path(s['source'])
	except HcpJsonPathError as e:
		raise HcpJsonPolicyError(f"{x}: invalid '{n}' source\n{e}")
def scope_valid_union(s, x, n):
	log(f"FUNC scope_valid_union running; {s},{x},{n}")
	scope_valid_common(s, x, n)
	if len(s) != 3 or 'source1' not in s or 'source2' not in s:
		raise HcpJsonPolicyError(
			f"{x}: '{n}' requires (only) 'source1' and 'source2'")
	try:
		if s['source1']:
			valid_path(s['source1'])
		valid_path(s['source2'])
	except HcpJsonPathError as e:
		raise HcpJsonPolicyError(f"{x}: invalid '{n}' source(s)\n{e}")
def scope_run_set(s, x, n, datanew, dataold):
	log(f"FUNC scope_run_set starting; {s},{x},{n}")
	path = s[n]
	value = s['value']
	log(f"path={path}, value={value}")
	res = overwrite_path(datanew, path, value)
	log(f"FUNC scope_run_set ending; {res}")
	return res
def scope_run_delete(s, x, n, datanew, dataold):
	log(f"FUNC scope_run_delete starting; {s},{x},{n}")
	path = s[n]
	log(f"path={path}")
	res = delete_path(datanew, path)
	log(f"FUNC scope_run_delete ending; {res}")
	return res
def scope_run_import(s, x, n, datanew, dataold):
	log(f"FUNC scope_run_import starting; {s},{x},{n}")
	path = s[n]
	source = s['source']
	log(f"path={path}, source={source}")
	ok, value = extract_path(dataold, source)
	if not ok:
		raise HcpJsonPolicyError(f"{x}: import: missing '{path}'")
	res = overwrite_path(datanew, path, value)
	log(f"FUNC scope_run_import ending; {res}")
	return res
def scope_run_union(s, x, n, datanew, dataold):
	log(f"FUNC scope_run_union starting; {s},{x},{n}")
	path = s[n]
	source1 = s['source1']
	source2 = s['source2']
	log(f"path={path}, source1={source1}, source2={source2}")
	ok, value2 = extract_path(datanew, source2)
	if not ok:
		raise HcpJsonPolicyError(f"{x}: union: missing '{source2}'")
	if source1 is not None:
		ok, value1 = extract_path(datanew, source1)
		if not ok:
			raise HcpJsonPolicyError(
				f"{x}: union: missing '{source1}'")
		value = union(value1, value2)
	else:
		value = value2
	res = overwrite_path(datanew, path, value)
	log(f"FUNC scope_run_union ending; {res}")
	return res

scopemeths = {
	'set': { 'is_valid': scope_valid_set, 'run': scope_run_set },
	'delete': { 'is_valid': scope_valid_delete, 'run': scope_run_delete },
	'import': { 'is_valid': scope_valid_import, 'run': scope_run_import },
	'union': { 'is_valid': scope_valid_union, 'run': scope_run_union }
}

# Shorthand. 'accrej' is for things like the "default" action, where literally
# only "accept" or "reject" are acceptable. 'noparam' is for secondary actions
# in a filter entry, ie. things like "on-return" and "otherwise". If a
# filter-entry has jump/call type fields, they are presumed to serve the
# primary "action" of that entry, not any of the secondary treatments.
accrej = [ 'accept', 'reject' ]
noparam = accrej + [ 'return', 'next' ]

# Check for top-level problems in a parsed policy that aren't detected during
# parsing. Ie. that references between filters are resolved.
def check_policy(policy):
	log("FUNC check_policy starting; {policy}")
	fs = policy['filters']
	s = policy['start']
	if s and s not in fs:
		raise HcpJsonPolicyError(
			f"'start' ({s}) doesn't match a valid filter")
	for x in fs:
		f = fs[x]
		log(f"processing filter: {x}, {f}")
		action = f['action']
		if action in [ 'jump', 'call' ]:
			dest = f[action]
			if dest not in fs:
				raise HcpJsonPolicyError(
					f"{x}: {action}: missing '{dest}'")
			if action == 'call' and 'on-return' in f and \
					f['on-return'] not in accrej:
				raise HcpJsonPolicyError(
					f"{x}: {action}: on-return: " +
					f"unknown '{f['on-return']}'")
		elif action not in noparam:
			raise HcpJsonPolicyError(
				f"{x}: action: unknown '{action}'")
		if 'next' in f and f['next'] not in fs:
			raise HcpJsonPolicyError(
				f"{x}: next: unknown '{f['next']}'")
	log("FUNC check_policy ending")

# Parse a "scope" attribute in a filter entry whose action is "call".
def parse_scope(s, x):
	log("FUNC parse_scope starting; {scope}")
	# We'll build an output scope and return it. This will be in the general
	# form.
	scope = []
	# If 's' is a simple string, convert it to the general form.
	if isinstance(s, str):
		s = [ { "import": ".", "source": s } ]
	if not isinstance(s, list):
		raise HcpJsonPolicyError(f"{x}: scope: bad type '{type(s)}'")
	# Iterate through the list of constructs for this scope
	for c in s:
		# Must have exactly one method. Note this logic closely follows
		# the 'if' handling in parse_filter().
		m = set(scopemeths.keys()).intersection(c.keys())
		if len(m) == 0:
			raise HcpJsonPolicyError(
				f"{x}: scope: no method in {c}")
		if len(m) != 1:
			raise HcpJsonPolicyError(
				f"{x}: scope: too many methods in {c} ({m})")
		m = m.pop()
		log(f"Processing method '{m}'")
		meth = scopemeths[m]
		meth['is_valid'](c, x, m)
		c['meth'] = m
	log("FUNC parse_scope ending")
	return s

# Run an already-parsed 'scope' against data, returning the transformed data
def run_scope(data, scope, x):
	log(f"FUNC run_scope starting; {x},{scope},{data}")
	result = {}
	for c in scope:
		methkey = c['meth']
		meth = scopemeths[methkey]
		result = meth['run'](c, x, methkey, result, data)
	log(f"FUNC run_scope ending")
	return result

# Parse a filter entry. This function is called for key-value pairs in the
# 'filters' dict, and by itself (recursively).
#
# If the value is a dict, the given kv pair forms a single filter entry in the
# output policy. In this case, the key serves as the default name for the
# filter entry unless it's overriden by a 'name' field.
#
# If the value is a list, then each of the list entries is itself parsed as a
# filter entry (recursion). But these entries are not kv pairs, so a key is
# created by using the original key (for the parent filter entry) and an
# incrementing suffix. Again, that will be the default name for the resulting
# filter entry unless it has a 'name' field to override it.
#
# Note that dict entries have no ordering, which has implications if a filter
# entry doesn't match: how do you continue to the next filter if there is no
# concept of 'next'? This is why lists are useful, as all but the final entry
# will have 'next' fields injected, connecting them. If filtering encounters a
# no-match-and-no-next condition, it can flag that as a filtering bug. (If you
# need 'next' behavior from a filter entry that is not in a list, or is at the
# end of a list, you must add the 'next' field yourself.)
def parse_filter(key, value, output_filters):
	log(f"FUNC parse_filter starting; {key},{value}")
	if isinstance(value, list):
		# The key-value pair describes a _sequence_ of filter entries,
		# not a single filter entry per se. So we iterate that list,
		# recursing for each entry, and the 'key' we pass in will be
		# derived from the current one, suffixed by an incrementing
		# counter.
		suffix = 0
		firstf = None
		lastf = None
		log(f"filter '{key}' is a list")
		for rf in value:
			newf = parse_filter(f"{key}_{suffix}", rf,
						output_filters)
			if lastf:
				if 'next' not in lastf:
					lastf['next'] = newf['name']
			else:
				output_filters[f"{key}"] = newf
			lastf = newf
			if not firstf:
				firstf = newf
			suffix += 1
		log(f"FUNC parse_filter ending; '{firstf['name']}'")
		return firstf
	# The key-value pair describes a single filter entry, so construct the
	# filter using key+value then insert it into 'output_filters'.
	# - the key becomes the filter name, unless overriden
	log(f"filter '{key}' is a struct")
	if 'name' not in value:
		log(f"setting name={key}")
		value['name'] = key
	x = value['name']
	if not isinstance(x, str):
		raise HcpJsonPolicyError(
			f"{key}: 'name' isn't a string ({type(x)})")
	# - action must be specified
	if 'action' not in value:
		raise HcpJsonPolicyError(f"{x}: action: missing")
	if not isinstance(value['action'], str):
		raise HcpJsonPolicyError(
			f"{x}: action: '{type(value['action'])}' not a string")
	action = value['action']
	# - if it's jump/call, sanity-check, but we can't confirm if
	#   the destination exists, that's check_policy().
	if action in [ 'jump', 'call' ]:
		if action not in value:
			raise HcpJsonPolicyError(f"{x}: {action}: missing")
		if not isinstance(value[action], str):
			raise HcpJsonPolicyError(
				f"{x}: {action}: '{type(value[action])}' " +
				"not a string")
	elif action not in noparam:
		raise HcpJsonPolicyError(f"{x}: action: '{action}' unknown")
	if action == 'call' and 'on-return' in value and \
			value['on-return'] not in noparam:
		raise HcpJsonPolicyError(
			f"{x}: on-return: unknown '{value['on-return']}'")
	if action == 'call' and 'scope' in value:
		# Parsing "scope" deserves its own function
		value['scope'] = parse_scope(value['scope'], x)
	# - if there's a 'next', it should be a string, but we can't
	#   confirm the destination exists, that's check_policy().
	if 'next' in value and not isinstance(value['next'], str):
		raise HcpJsonPolicyError(
			f"{x}: next: '{value['next']}' not a string")
	# - if there's a condition, process it
	if 'if' in value:
		vif = value['if']
		if isinstance(vif, list):
			log(f"{x}: parsing list of 'if' conditions;")
			andlist = vif
		else:
			log(f"{x}: parsing single 'if' condition;")
			andlist = [ vif ]
		for vif in andlist:
			log(f"{x}: if: {vif}")
			# The following could become "check_condition(vif)"
			# - it has to be a struct
			if not isinstance(vif, dict):
				raise HcpJsonPolicyError(
					f"{x}: if: entry isn't a dict")
			# - it must have exactly one condition type in it
			m = set(conds.keys()).intersection(vif.keys())
			if len(m) == 0:
				raise HcpJsonPolicyError(f"{x}: if: no method")
			if len(m) != 1:
				raise HcpJsonPolicyError(
					f"{x}: if: too many methods '{m}'")
			m = m.pop()
			log(f"method={m}")
			cond = conds[m]
			# - and that condition has to like what it sees
			cond['is_valid'](vif, x, m)
			# Cache the info required to run the evaluation
			vif['cond'] = m
	# - if there's an "otherwise", it must be parameter-less
	if 'otherwise' in value:
		vo = value['otherwise']
		if not isinstance(vo, str):
			raise HcpJsonPolicyError(
				f"{x}: otherwise: '{vo}' not a string")
		if vo not in noparam:
			raise HcpJsonPolicyError(
				f"{x}: otherwise: unknown '{vo}'")
	# - add the filter entry, but it must not collide
	if x in output_filters:
		raise HcpJsonPolicyError(f"{x}: filter name conflict '{x}'")
	output_filters[x] = value
	log(f"FUNC parse_filter ending; '{value['name']}'")
	return value

# Return a policy object that we can trust, which is parsed and sanity-checked
# from a JSON encoding. This will throw HcpJsonPolicyError if we find a
# problem, otherwise JSONDecodingError if the JSON decoder hits something.
def parse(jsonstr):
	log(f"FUNC parse starting")
	policy = json.loads(jsonstr)
	log(f"input policy = {policy}")
	if not isinstance(policy, dict):
		raise HcpJsonPolicyError(
			f"Policy must be a 'dict' (not {type(policy)})")
	# Check 'start' and 'default'
	if 'start' in policy:
		if not isinstance(policy['start'], str):
			raise HcpJsonPolicyError(
				f"start: '{policy['start']}' not a string")
	else:
		log("setting start = None")
		policy['start'] = None
	if 'default' in policy:
		if not isinstance(policy['default'], str):
			raise HcpJsonPolicyError(
				f"default: '{policy['default']}' not a string")
		if policy['default'] not in accrej:
			raise HcpJsonPolicyError(
				f"default: '{policy['default']}' not accept/reject")
	else:
		log("setting default = reject")
		policy['default'] = "reject"
	# We pop the 'filters' _out_ of 'policy', build a list of
	# "output_filters" via whatever parse_filter() produces while looking
	# at those popped filters, then insert "output_filters" back _into_ the
	# policy. This is how a list-typed entry (a chain) gets replaced with
	# multiple entries (with 'next's filled in).
	if 'filters' not in policy:
		raise HcpJsonPolicyError("filters: missing")
	filters = policy.pop('filters')
	if not isinstance(filters, dict):
		raise HcpJsonPolicyError(
			f"filters: must be dict (not {type(filters)})")
	# Build a new 'filters' set from the old one
	output_filters = {}
	for i in filters:
		f = parse_filter(i, filters[i], output_filters)
		if not policy['start']:
			log(f"setting start = {f['name']}")
			policy['start'] = f
	policy['filters'] = output_filters
	# This checks for things that we can't check during construction of
	# 'output', particularly the cross-references between filters. It also
	# optimizes the policy - eg. by replacing text condition names
	# ("exist", "not-equal", etc) with the functions that implement them.
	check_policy(policy)
	log(f"FUNC parse ending; {policy}")
	return policy

# Pass the JSON data through the fully-formed policy object.
def run_sub(filters, cursor, data):
	log(f"FUNC run_sub starting")
	log(f"filters={json.dumps(filters)}")
	while True:
		log(f"cursor={cursor}")
		f = filters[cursor]
		log(f"filter={json.dumps(f)}")
		action = f['action']
		name = f['name']
		log(f"name={name}, action={action}")
		x = name
		if 'if' in f:
			i = f['if']
			if isinstance(i, list):
				log(f"{x}: processing list of 'if' conditions;")
				andlist = i
			else:
				log(f"{x}: processing single 'if' condition;")
				andlist = [ i ]
			finalb = True
			for i in andlist:
				log(f"{x}: if: {i}")
				c = i['cond']
				cond = conds[c]
				b = cond['run'](i, name, c, data)
				if not b:
					log(f"{x}: if: got a False, leaving loop")
					finalb = False
					break
			if not finalb:
				if 'otherwise' in f:
					action = f['otherwise']
					log(f"{x}: if: no match -> {action}")
				else:
					action = 'next'
					log("{x}: if: no match -> next")
			else:
				log(f"{x}: if: match -> {action}")
		if action == 'return':
			log(f"FUNC run_sub ending; 'return'")
			return None
		if action == 'call':
			log(f"{x}: call: preparing to call '{f['call']}'")
			# Call -> recurse
			scope = '.'
			if 'scope' in f:
				scope = f['scope']
				scoped_data = run_scope(data, scope, name)
			else:
				scoped_data = data
			log(f"{x}: call: calling '{f['call']}'")
			suboutput = run_sub(filters, f['call'], scoped_data)
			if suboutput:
				log(f"{x}: call: got a decision back, passing it along")
				log(f"FUNC run_sub ending; {suboutput}")
				return suboutput
			log(f"{x}: call: no decision yet")
			if 'on-return' in f:
				action = f['on-return']
				log(f"{x}: on-return: -> {action}")
			else:
				action = 'next'
				log(f"{x}: call: -> next")
		if action == 'jump':
			cursor = f['jump']
			log(f"{x}: jump: -> '{cursor}'")
			# Jump -> move cursor and restart the loop
			continue
		if action == 'next':
			if 'next' not in f:
				raise HcpJsonPolicyError(f"{x}: {next}: missing")
			cursor = f['next']
			log(f"{x}: next: -> {cursor}")
			continue
		if action not in accrej:
			raise HcpJsonPolicyError(
				f"{x}: unhandled 'action' ({action})")
		log(f"FUNC run_sub ending; {x},{action}")
		return {
			'action': action,
			'last_filter': name,
			'reason': 'Filter match'
		}

# if 'dataUseVars' is set True, parameter expansion will be performed on 'data'
# and 'policy' before filtering occurs, using variables found in 'data' (at the
# field identified by 'dataVarsKey'). In this case, those parameter-expansion
# vars are removed from of 'data' before transforming 'data' and 'policy. If
# 'dataKeepsVars' is True, the variables will be added back to the 'data'
# structure once expansion is done.
def run(policyjson, data, stripComments = True,
		dataUseVars = True,
		dataVarsKey = '__env',
		dataKeepsVars = False):
	log(f"FUNC run starting")
	log(f"- stripComments={stripComments}")
	log(f"- dataUseVars={dataUseVars}")
	log(f"- dataVarsKey={dataVarsKey}")
	log(f"- dataKeepsVars={dataKeepsVars}")
	log(f"- policyjson={policyjson}")
	log(f"- data(JSON)={json.dumps(data)}")
	# Serialize and deserialize the hierarchical 'data' object to be sure
	# that parameter expansion doesn't have any side-effect beyond this
	# call. Also, we take a string 'policyjson' input to emphasize that the
	# user shouldn't have used our 'parse' method yet, because that
	# post-processes the json.loads() output and we want that to occur
	# _after_ parameter-expansion, not before.
	data = json.loads(json.dumps(data))
	policy = parse(policyjson)
	if stripComments:
		log("running strip_comments() on policy and data")
		strip_comments(policy)
		strip_comments(data)
	if dataUseVars:
		_vars = data.pop(dataVarsKey, {})
		data = HcpJsonExpander.process_obj(_vars, data)
		if dataKeepsVars:
			data[dataVarsKey] = _vars
		policy = HcpJsonExpander.process_obj(_vars, policy)
	output = run_sub(policy['filters'], policy['start'], data)
	if not output:
		log("setting default output (run_sub returned 'None')")
		output = {
			'action': policy['default'],
			'last_filter': None,
			'reason': 'Default filter action'
		}
	log(f"FUNC run ending; {output}")
	return output
