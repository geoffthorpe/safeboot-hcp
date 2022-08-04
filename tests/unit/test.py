#!/usr/bin/python3

import json
import sys

# If there's trouble, uncomment the following two lines and use;
#   pp.pprint(anydatastructure)
#import pprint
#pp = pprint.PrettyPrinter(indent=4)

sys.path.insert(1, '/hcp/xtra')

import HcpEnvExpander

c_pairs1_input = open('c_pairs1_input.json', 'r').read()
c_pairs1_unexpanded = HcpEnvExpander.loads(c_pairs1_input, autoexpand=False)
c_pairs1_expanded = HcpEnvExpander.loads(c_pairs1_input)

c_pairs1_txt_output = open('c_pairs1_output.json', 'r').read()
c_pairs1_output = json.loads(c_pairs1_txt_output)
result = c_pairs1_expanded == c_pairs1_output
print(f"c_pairs1 -> {result}")
if result != True:
	print('NO MATCH')
	sys.exit(1)

import HcpJsonPolicy

c_policy1_pol1 = HcpJsonPolicy.loads(open('c_policy1_pol1.json', 'r').read())
c_policy1_input1 = json.loads(open('c_policy1_input1.json', 'r').read())
result = HcpJsonPolicy.run(c_policy1_pol1, c_policy1_input1)
print(f"c_policy1_pol1 -> {result}")
if result != "reject":
	sys.exit(1)

c_policy1_pol2 = HcpJsonPolicy.loads(open('c_policy1_pol2.json', 'r').read())
result = HcpJsonPolicy.run(c_policy1_pol2, c_policy1_input1)
print(f"c_policy1_pol2 -> {result}")
if result != "accept":
	sys.exit(1)

c_policy1_pol3 = HcpJsonPolicy.loads(open('c_policy1_pol3.json', 'r').read())
result = HcpJsonPolicy.run(c_policy1_pol3, c_policy1_input1)
print(f"c_policy1_pol3 -> {result}")
if result != "accept":
	sys.exit(1)

result = HcpJsonPolicy.run(c_policy1_pol3, c_policy1_pol3)
print(f"c_policy1_pol3 -> {result}")
if result != "reject":
	sys.exit(1)

result = HcpJsonPolicy.run_with_env(
		open('c_policy2_pol1.json', 'r').read(),
		open('c_policy2_input1.json', 'r').read())
print(f"c_policy2_pol1 -> {result}")
if result != "accept":
	sys.exit(1)

result = HcpJsonPolicy.run_with_env(
		open('c_policy2_pol2.json', 'r').read(),
		open('c_policy2_input1.json', 'r').read())
print(f"c_policy2_pol2 -> {result}")
if result != "reject":
	sys.exit(1)

result = HcpJsonPolicy.run_with_env(
		open('c_policy2_pol3.json', 'r').read(),
		open('c_policy2_input1.json', 'r').read())
print(f"c_policy2_pol3 -> {result}")
if result != "accept":
	sys.exit(1)

import HcpRecursiveUnion

c_union1_a = {
	'field1': 39,
	'field2': [ 'a', 12, 'dog' ],
	'field3': { 'a', 'b', 'c' },
	'field4': {
		'a': 12,
		'b': [ 'this', 'is', 0 ],
		'c': { 3, 6, 'cat' },
		'd': {
			'foo': 'bar'
		}
	}
}
c_union1_b = {
	'field5': 'whatever',
	'field4': {
		'd': {
			'yoo': 'hoo'
		}
	}
}
c_union1_out = {
	'field1': 39,
	'field2': [ 'a', 12, 'dog' ],
	'field3': { 'a', 'b', 'c' },
	'field4': {
		'a': 12,
		'b': [ 'this', 'is', 0 ],
		'c': { 3, 6, 'cat' },
		'd': {
			'foo': 'bar',
			'yoo': 'hoo'
		},
	},
	'field5': 'whatever'
}
c_union2_c = {
	'field1': 39,
	'field2': None,
	'field4': [ 1, 2, 3 ]
}
c_union2_out = {
	'field1': 39,
	'field2': None,
	'field3': { 'a', 'b', 'c' },
	'field4': [ 1, 2, 3 ]
}
sresult = HcpRecursiveUnion.union(c_union1_a,c_union1_b)
result = sresult == c_union1_out
print(f"c_union1 -> {result}")
if not result:
	sys.exit(1)
sresult = HcpRecursiveUnion.union(c_union1_a,c_union2_c)
result = sresult == c_union2_out
print(f"c_union2 -> {result}")
if not result:
	sys.exit(1)
