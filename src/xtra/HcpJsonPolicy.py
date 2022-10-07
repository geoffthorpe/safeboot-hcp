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

# Shorthand
accrej = [ 'accept', 'reject' ]
accrejret = accrej + [ 'return' ]

# Check for top-level problems in a parsed policy that aren't detected during
# parsing. Ie. that references between filters are resolved.
def check_policy(policy):
	fs = policy['filters']
	s = policy['start']
	if s and s not in fs:
		raise HcpJsonPolicyError(
			f"'start' ({s}) doesn't match a valid filter")
	for x in fs:
		f = fs[x]
		action = f['action']
		if action in [ 'jump', 'call' ]:
			dest = f[action]
			if dest not in fs:
				raise HcpJsonPolicyError(
					f"{x}: invalid {action} ({dest})")
			if action == 'call' and 'on-return' in f and \
					f['on-return'] not in accrej:
				raise HcpJsonPolicyError(
					f"{x}: invalid 'on-return'")
		elif action not in accrejret:
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
	elif action not in accrejret:
		raise HcpJsonPolicyError(f"{x}: unknown 'action' ({action})")
	if action == 'call' and 'on-return' in value and \
			value['on-return'] not in accrejret:
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
		# This is the filter we act on _unless_ (a) there's an 'if'
		# clause, and (b) the clause returns False.
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
		if action == 'next':
			if not f['next']:
				raise HcpJsonPolicyError(f"{name}: no next filter")
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
