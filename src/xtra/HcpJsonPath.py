import re

valid_path_node_re = '[A-Za-z_][A-Za-z0-9_-]*'
valid_path_node_prog = re.compile(valid_path_node_re)

class HcpJsonPathError(Exception):
	pass

def valid_path_node(node):
	if not valid_path_node_prog.fullmatch(node):
		raise HcpJsonPathError(f"HCP JSON, invalid path node: {node}")

def path_pop_node(path):
	if len(path) < 1:
		return None, path
	if path[0:1] != ".":
		raise HcpJsonPathError(f"HCP JSON, path nodes must begin with '.': {path}")
	path = path[1:]
	index = path.find(".")
	if index == 0:
		raise HcpJsonPolicyError(f"Policy JSON, path nodes must be non-empty: {path}")
	if index < 0:
		node = path
		path = ""
	else:
		node = path[0:index]
		path = path[index:]
	valid_path_node(node)
	return node, path

def valid_path(path):
	if not isinstance(path, str):
		raise HcpJsonPathError("HCP JSON, path is not a string")
	if path == ".":
		return
	while True:
		node, path = path_pop_node(path)
		if len(path) == 0:
			return
