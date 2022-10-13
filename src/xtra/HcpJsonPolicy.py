# This 'policy' abstraction interprets a JSON configuration file and, from it,
# implements a filtering scheme that acts much like a set of packet-filter
# rules. (As such, the terms 'rule' and 'filter' will be used interchangeably.)
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
#         from the call, otherwise the "next" semantic is assumed.
#
#     "on-return": <"accept", "reject", "return", or "next" (the default)>
#         Optional. Not used unless action==call and control returns from the
#         call.
#
#     "next": <string naming the rule to pass control to>
#         Only required if action==next (which is probably a silly thing to do)
#         or if the rule has a conditional that sometimes evaluates false
#         (which is less silly). This field can be supplied explicitly, but it
#         is usually filled in by post-processing. Read on to find out when and
#         why. (See "chains".)
#
#     "if": <struct containing one or two key-value pairs>
#         Optional. Specifies a condition which must be true for the rule"s
#         "action" to be performed. (If the condition evaluates false, the
#         "otherwise" action will be taken, if defined, otherwise the "next"
#         semantic is assumed.)
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
#           "regular1": { "action": "reject", "if": { ... } ... },
#           "chain1": [
#               { "action": "reject", "if": { ... } ... },
#               { "action": "accept", "if": { ... } ... },
#               { "name": "foo1", "action": "accept", "if": { ... } ... },
#               { "action": "reject" },
#           ]
#       }
#  After post-processing;
#       "filters": {
#           "regular1": { "action": "reject", "if": { ... } ... },
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

import json

from HcpJsonPath import valid_path_node, valid_path, path_pop_node, extract_path, HcpJsonPathError
import HcpEnvExpander

class HcpJsonPolicyError(Exception):
	pass

# This is noisy even for autopurged debugging logs. You'll probably only want
# to enable this if you have a unit test that reproduces your problem.
if False:
	import pprint
	ppp = pprint.PrettyPrinter()
	pp = ppp.pprint
	def foo(s):
		print(s)
else:
	def foo(s):
		pass
	pp = foo

# Condition-handling for "if" filters. 'condbase' defines the set of
# conditions, that can be evaluated, together with functions to (a) confirm
# that the condition is well-formed, and (b) evaluate the condition against an
# input. The 'is_valid' function raises a HcpJsonPolicyError if the condition
# structure is malformed. The 'run' function returns a boolean to indicate the
# result of the condition operating on the input.
def is_valid_exist(c, x, n):
	if len(c) != 1 or not isinstance(c[n], str):
		raise HcpJsonPolicyError(f"{x}: invalid '{n}' condition")
	try:
		valid_path(c[n])
	except HcpJsonPathError as e:
		raise HcpJsonPolicyError(f"{x}: invalid '{n}' path\n{e}")
def is_valid_equal(c, x, n):
	if len(c) != 2 or not isinstance(c[n], str) or 'value' not in c:
		raise HcpJsonPolicyError(f"{x}: invalid '{n}' condition")
	try:
		valid_path(c[n])
	except HcpJsonPathError as e:
		raise HcpJsonPolicyError(f"{x}: invalid '{n}' path\n{e}")
def run_exist(c, x, n, data):
	path = c[n]
	ok, _ = extract_path(data, path)
	return ok
def run_equal(c, x, n, data):
	path = c[n]
	ok, data = extract_path(data, path)
	if not ok:
		return False
	foo("run_equal;")
	pp(c['value'])
	pp(data)
	if not c['value'] == data:
		foo("which apparently don't match")
	return c['value'] == data
condbase = {
	'exist': { 'is_valid': is_valid_exist, 'run': run_exist },
	'equal': { 'is_valid': is_valid_equal, 'run': run_equal }
}
# Create negated versions of the base conditions
condneg = {
	f"not-{k}": {
		'is_valid': lambda c, x, n: v['is_valid'](c, x, n),
		'run': lambda c, x, n, d: not v['run'](c, x, n, d)
	} for (k, v) in condbase.items()
}
conds = condbase | condneg

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
	foo("check_policy() starting")
	fs = policy['filters']
	s = policy['start']
	foo(f"start={s}")
	foo(f"filters.keys()={fs.keys()}")
	if s and s not in fs:
		raise HcpJsonPolicyError(
			f"'start' ({s}) doesn't match a valid filter")
	for x in fs:
		foo(f"processing {x}")
		f = fs[x]
		action = f['action']
		if action in [ 'jump', 'call' ]:
			foo(f"action={action}")
			dest = f[action]
			foo(f"{action}={dest}")
			if dest not in fs:
				raise HcpJsonPolicyError(
					f"{x}: invalid {action} ({dest})")
			if action == 'call' and 'on-return' in f and \
					f['on-return'] not in accrej:
				raise HcpJsonPolicyError(
					f"{x}: invalid 'on-return'")
		elif action not in noparam:
			raise HcpJsonPolicyError(
				f"{x}: invalid 'action' ({action})")
		if 'next' in f and f['next'] not in fs:
			raise HcpJsonPolicyError(
				f"{x}: invalid 'next' ({f['next']})")

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
	if isinstance(value, list):
		# The key-value pair describes a _sequence_ of filter entries,
		# not a single filter entry per se. So we iterate that list,
		# recursing for each entry, and the 'key' we pass in will be
		# derived from the current one, suffixed by an incrementing
		# counter.
		suffix = 0
		lastf = None
		foo(f"parse_filter({key}) is a list")
		for rf in value:
			newf = parse_filter(f"{key}_{suffix}", rf,
						output_filters)
			if lastf:
				if 'next' not in lastf:
					lastf['next'] = newf['name']
			else:
				output_filters[f"{key}"] = newf
			lastf = newf
			suffix += 1
		return lastf
	# The key-value pair describes a single filter entry, so construct the
	# filter using key+value then insert it into 'output_filters'.
	# - the key becomes the filter name, unless overriden
	foo(f"parse_filter({key}) is a struct")
	if 'name' not in value:
		value['name'] = key
	x = value['name']
	if not isinstance(x, str):
		raise HcpJsonPolicyError(f"{key}: 'name' isn't a string")
	# - action must be specified
	if 'action' not in value or not isinstance(value['action'], str):
		raise HcpJsonPolicyError(f"{x}: 'action' field invalid")
	action = value['action']
	# - if it's jump/call, sanity-check, but we can't confirm if
	#   the destination exists, that's check_policy().
	if action in [ 'jump', 'call' ]:
		if action not in value or not isinstance(value[action], str):
			raise HcpJsonPolicyError(f"{x}: invalid {action}")
	elif action not in noparam:
		raise HcpJsonPolicyError(f"{x}: unknown 'action' ({action})")
	if action == 'call' and 'on-return' in value and \
			value['on-return'] not in noparam:
		raise HcpJsonPolicyError(
			f"{x}: invalid 'on-return' ({value['on-return']})")
	# - if there's a 'next', it should be a string, but we can't
	#   confirm the destination exists, that's check_policy().
	if 'next' in value and not isinstance(value['next'], str):
		raise HcpJsonPolicyError(
			f"{x}: invalid 'next' ({value['next']})")
	# - if there's a condition, process it
	if 'if' in value:
		vif = value['if']
		# The following could become "check_condition(vif)"
		# - it has to be a struct
		if not isinstance(vif, dict):
			raise HcpJsonPolicyError(f"{x}: 'if' isn't a dict")
		# - it must have exactly one condition type in it
		m = set(conds.keys()).intersection(vif.keys())
		if len(m) != 1:
			raise HcpJsonPolicyError(f"{x}: 'if' must have one " +
					f"condition (not {len(m)})")
		m = m.pop()
		cond = conds[m]
		# - and that condition has to like what it sees
		cond['is_valid'](vif, x, m)
		# Cache the info required to run the evaluation
		vif['cond'] = m
	# - if there's an "otherwise", it must be parameter-less
	if 'otherwise' in value:
		vo = value['otherwise']
		if not isinstance(vo, str) or vo not in noparam:
			raise HcpJsonPolicyError(
				f"{x}: invalid 'otherwise' ({vo})")
	# - add the filter entry, but it must not collide
	if x in output_filters:
		raise HcpJsonPolicyError(f"{x}: conflict on filter")
	output_filters[x] = value
	return value

# Return a policy object that we can trust, which is parsed and sanity-checked
# from a JSON encoding. This will throw HcpJsonPolicyError if we find a
# problem, otherwise JSONDecodingError if the JSON decoder hits something.
def loads(jsonstr):
	policy = json.loads(jsonstr)
	if not isinstance(policy, dict):
		raise HcpJsonPolicyError(
			f"Policy must be a 'dict' (not {type(policy)})")
	# Check 'start' and 'default'
	if 'start' in policy and not isinstance(policy['start'], str):
		raise HcpJsonPolicyError(f"'start' must be a string")
	if 'start' not in policy:
		policy['start'] = None
	if 'default' in policy:
		if not isinstance(policy['default'], str):
			raise HcpJsonPolicyError(f"'default' must be a string")
		if policy['default'] not in accrej:
			raise HcpJsonPolicyError(
				f"'default' must be accept/reject (not {d})")
	else:
		policy['default'] = "reject"
	# We pop the 'filters' _out_ of 'policy', build a list of
	# "output_filters" via whatever parse_filter() produces while looking
	# at those popped filters, then insert "output_filters" back _into_
	# the policy.
	if 'filters' not in policy:
		raise HcpJsonPolicyError("Missing 'filters' field")
	filters = policy.pop('filters')
	if not isinstance(filters, dict):
		raise HcpJsonPolicyError(
			f"'filters' must be of type dict (not {type(filters)})")
	# Build a new 'filters' set from the old one
	output_filters = {}
	for i in filters:
		f = parse_filter(i, filters[i], output_filters)
		if not policy['start']:
			policy['start'] = f
	policy['filters'] = output_filters
	# This checks for things that we can't check during construction of
	# 'output', particularly the cross-references between filters. It also
	# optimizes the policy - eg. by replacing text condition names
	# ("exist", "not-equal", etc) with the functions that implement them.
	check_policy(policy)
	return policy

def load(jsonpath):
	return loads(open(jsonpath, "r").read())

# Pass the JSON data through the fully-formed policy object.
def run_sub(filters, cursor, data):
	foo(f"run_sub(,{cursor},) starting")
	while True:
		f = filters[cursor]
		action = f['action']
		name = f['name']
		foo(f"name={name}, action={action}")
		pp(f)
		if 'if' in f:
			i = f['if']
			c = i['cond']
			foo(f"condition check, c={c}")
			cond = conds[c]
			b = cond['run'](i, name, c, data)
			foo(f"check returned {b}")
			if not b:
				if 'otherwise' in f:
					action = f['otherwise']
					foo(f"doesn't match -> {action}")
				else:
					foo("doesn't match -> next")
					action = 'next'
			else:
				foo(f"match -> {action}")
		if action == 'return':
			foo("returning None")
			return None
		if action == 'call':
			# Call -> recurse
			foo(f"calling {f['call']}")
			suboutput = run_sub(filters, f['call'], data)
			if suboutput:
				foo(f"got output, passing it along")
				pp(suboutput)
				return suboutput
			foo("got no output -> next")
			action = 'next'
			if 'on-return' in f:
				action = f['on-return']
				foo(f"got no ouput, on-return -> {action}")

			else:
				foo("got no output -> next")
		if action == 'jump':
			# Jump -> move cursor and restart the loop
			cursor = f['jump']
			foo(f"jumping to {cursor}")
			continue
		# 'next' is a little special. It's an implicit target, used
		# when the filter entry does _not_ match the input (and
		# therefore the action doesn't depend on anything in that
		# entry). And static checking (per check_policy() above) cannot
		# generally "know" whether the set of potential inputs will or
		# won't require 'next' attributes in places where they're not
		# present. As such, we don't want to throw an exception when
		# performing a 'next' action on an entry that doesn't have one,
		# instead treat it like a rejection and set a 'reason' field
		# that should alert someone to the bug in their JSON config
		if action == 'next':
			if 'next' not in f:
				return {
					'action': 'reject',
					'last_filter': name,
					'reason': "bug in policy.json - no 'next'"
				}
			cursor = f['next']
			foo(f"next -> {cursor}")
			continue
		if action not in accrej:
			raise HcpJsonPolicyError(
				f"{name}: unhandled 'action' ({action})")
		foo(f"action -> {action}")
		return {
			'action': action,
			'last_filter': name,
			'reason': 'Filter match'
		}
def run(policy, data):
	foo("run() starting, will call run_sub()")
	pp(data)
	output = run_sub(policy['filters'], policy['start'], data)
	foo("run() back from run_sub()")
	print(f"output={output}")
	if output:
		return output
	return {
		'action': policy['default'],
		'last_filter': None,
		'reason': 'Default filter action'
	}

# Wrapper function to deal with input that has embedded '__env'. That "env" is
# decoded and fully self-expanded, then it is used to expand both the input and
# the policy, after which the policy is run. The "env" section is removed from
# the input before it undergoes expansion and policy filtering. If the
# fully-self-expanded "env" should be in the data that undergoes policy
# filtering, set 'includeEnv=True'. Expansion requires string (JSON)
# representation, so this wrapper consumes unparsed string inputs rather than
# python structs.
def run_with_env(policyjson, datajson, includeEnv=False):
	data = json.loads(datajson)
	env = data.pop('__env', {})
	datajson = json.dumps(data)
	HcpEnvExpander.env_check(env)
	envjson, env = HcpEnvExpander.env_selfexpand(env)
	datajson = HcpEnvExpander.env_expand(datajson, env)
	policyjson = HcpEnvExpander.env_expand(policyjson, env)
	policy = loads(policyjson)
	data = json.loads(datajson)
	if includeEnv:
		data['__env'] = env
	return run(policy, data)
