import os
import sys
import datetime

from hcp_common import env_get_dir_or_none

class HcpErrorTracefile(Exception):
	pass

def tracefile(name, dirpath = None):
	now = datetime.datetime.now(datetime.timezone.utc)
	suffix = f"{now.year:04}:{now.month:02}:{now.day:02}:{now.hour:02}"
	if not dirpath:
		dirpath = env_get_dir_or_none('HCP_TRACEFILE')
	if not dirpath:
		dirpath = env_get_dir_or_none('HOME')
	if not dirpath:
		raise HcpErrorTracefile(f"Can't find HCP_TRACEFILE/HOME directory")
	tracefile = open(f"{dirpath}/debug-{name}-{suffix}", 'a')
	print(f"{name}: tracefile going to {tracefile.name}", file = sys.stderr)
	return tracefile
