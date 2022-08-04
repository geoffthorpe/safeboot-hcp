import json

from HcpJsonPath import valid_path_node, valid_path, path_pop_node
import HcpEnvExpander

autolabel = 0

class HcpJsonPolicyError(Exception):
	pass

def verify_filter_name(name):
	if not isinstance(name, str):
		raise HcpJsonPolicyError("Policy JSON, 'name' field is not a string")

def verify_filter_result(result):
	if not isinstance(result, str):
		raise HcpJsonPolicyError("Policy JSON, 'result' field is not a string")
	if result != "accept" and result != "reject":
		raise HcpJsonPolicyError(
			f"Policy JSON, neither 'accept' nor 'reject': {result}")

def parse_filter_pvpair(pvpair):
	if not isinstance(pvpair, dict):
		raise HcpJsonPolicyError("Policy JSON, condition is not a dict")
	if len(pvpair.keys()) != 2 or 'path' not in pvpair or 'value' not in pvpair:
		raise HcpJsonPolicyError("Policy JSON, condition is not 'path'+'value'")
	valid_path(pvpair['path'])
	return {
		'path': pvpair['path'],
		'value': pvpair['value']
	}

def parse_filter_equality(pvlist, key):
	if not isinstance(pvlist, list):
		raise HcpJsonPolicyError(f"Policy JSON, '{key}' is not a list")
	if len(pvlist) == 0:
		raise HcpJsonPolicyError(f"Policy JSON, '{key}' list is empty")
	cond = {
		'type': key,
		'pvpairs': []
	}
	for pvpair in pvlist:
		cond['pvpairs'].append(parse_filter_pvpair(pvpair))
	return cond

def parse_filter_entry(entry):
	if not isinstance(entry, dict):
		raise HcpJsonPolicyError("Policy JSON, 'filters' entry is not a dict")
	if len(entry.keys()) == 0:
		raise HcpJsonPolicyError("Policy JSON, 'filters' entry is empty")
	filterentry = {
		"conditions": [],
		"result": "continue"
	}
	for key in entry:
		value = entry[key]
		if key == "name":
			verify_filter_name(value)
			filterentry['name'] = value
		elif key == "label":
			filterentry['label'] = value
		elif key == "if-equal" or key == "unless-equal":
			filterentry['conditions'].append(
				parse_filter_equality(value, key))
		elif key == "result":
			verify_filter_result(value)
			filterentry['result'] = value
		else:
			raise HcpJsonPolicyError(f"Policy JSON, unrecognized field: {key}")
	if 'label' not in filterentry:
		global autolabel
		filterentry['label'] = f"label_{autolabel}"
		autolabel += 1
	return filterentry

def parse_filters(data):
	if not isinstance(data, list):
		raise HcpJsonPolicyError("Policy JSON 'filters' is not a list")
	outcome = { 'filters': [] }
	for i in data:
		outcome['filters'].append(parse_filter_entry(i))
	return outcome

def loads(jsonstr):
	rawstruct = json.loads(jsonstr)
	if 'filters' not in rawstruct:
		raise HcpJsonPolicyError("Policy JSON: no 'filters'")
	outcome = parse_filters(rawstruct['filters'])
	if 'default' in rawstruct:
		verify_filter_result(rawstruct['default'])
		outcome['default'] = rawstruct['default']
	else:
		outcome['default'] = "reject"
	return outcome

def load(jsonpath):
	return loads(open(jsonpath, "r").read())

def run_filter_pvpair(pvpair, data):
	# The complexity is to drill into data as path of nested dicts using
	# the 'path' in pvpair, as a "."-delimited sequence of key names. Once
	# the path-identified property in the data has been found, the actual
	# equality-checking is simply python's "==", which seems to do the
	# right thing. (Checking the structure recursively, treating different
	# types (dict, list, string, int) as automatically unequal, etc.)
	obj = data
	path = pvpair['path']
	value = pvpair['value']
	valid_path(path)
	if path != ".":
		while True:
			node, path = path_pop_node(path)
			if not isinstance(obj, dict):
				return False
			if node not in obj:
				return False
			obj = obj[node]
			if len(path) == 0:
				break
	return obj == value

def run_filter_equality(pvlist, data):
	for pvpair in pvlist:
		if not run_filter_pvpair(pvpair, data):
			return False
	return True

def run_filter_entry(entry, data):
	for i in entry['conditions']:
		if i['type'] == "if-equal":
			condtype = True
		elif i['type'] == "unless-equal":
			condtype = False
		else:
			raise Exception("BUG in run_filter_entry")
		allmatch = run_filter_equality(i['pvpairs'], data);
		if (condtype and not allmatch) or (not condtype and allmatch):
			return False
	return True

# Note: the policy must already have any/all parameter expansion performed
# because it is no longer a JSON string, it's a python struct! Ie. parameter
# expansion can only occur on JSON, _before_ it gets json.loads()ed.
def run(policy, data):
	for i in policy['filters']:
		label = i['label']
		allmatch = run_filter_entry(i, data)
		if allmatch:
			result = i['result']
			if result == "reject" or result == "accept":
				return result
		# no filter made a decision, so keep looping
	return policy['default']

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
