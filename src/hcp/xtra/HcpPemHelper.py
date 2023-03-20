import subprocess
import sys

# This is just a holding pen for miscellaneous utilities that deal with PEM
# files and "openssl x509" and what-not.

class HcpPemError(Exception):
	pass

# We're seeing tab characters in the client certs that nginx forwards along.
def pem_clean(s):
	return s.strip().replace('\t', '')

baseargs = [ 'openssl', 'x509', '-inform', 'PEM', '-noout' ]

def get_email_address(s):
	args = baseargs + [ '-email' ]
	s = pem_clean(s)
	c = subprocess.run(args, text = True, input = s,
			   stdout = subprocess.PIPE)
	if c.returncode != 0:
		raise HcpPemError(f"HCP PEM, subprocess failure: '{args}'")
	res = c.stdout.strip().split('\n')
	if len(res) == 0:
		return None
	if len(res) == 1:
		return res.pop()
	return res
