import re

re_valid_hostname_char = "[A-Za-z0-9_-]"
re_valid_hostname_node = f"{re_valid_hostname_char}+"
re_valid_hostname_withdot = f"\.{re_valid_hostname_node}"
re_valid_hostname = f"{re_valid_hostname_node}({re_valid_hostname_withdot})*"

valid_hostname_prog = re.compile(re_valid_hostname)

class HcpHostnameError(Exception):
	pass

def valid_hostname(hostname):
	if not valid_hostname_prog.fullmatch(hostname):
		raise HcpHostnameError(f"HCP, invalid hostname: {hostname}")

def pop_hostname(hostname):
	index = hostname.find(".")
	if index == 0:
		raise HcpHostnameError(f"HCP, hostname components must be non-empty: {hostname}")
	if index < 0:
		node = hostname
		hostname = ""
	else:
		node = hostname[0:index]
		hostname = hostname[index+1:]
	return node, hostname

def dc_hostname(hostname):
	result = ""
	while True:
		node, hostname = pop_hostname(hostname)
		if node == "":
			break;
		if result == "":
			result = f"DC={node}"
		else:
			result = f"{result},DC={node}"
	return result
