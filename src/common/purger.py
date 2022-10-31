#!/usr/bin/python3
# This purger tool is used to clear out files that "get too old". The
# motivating use-case is where logically-distinct software components produce
# detailed logs for debugging and diagnosis and we want to reap old logs so
# the filesystem usage stays bounded.
#
# The tool consumes a configuration file on start-up, which is JSON format and
# described further down. At run-time, the tool runs a periodic "purge" loop
# that does the following;
# - it scans a configured directory (see "dir") for purge recipes, which are
#   also in JSON format and will also be described shortly.
# - each recipe specifies the files that should be considered for purging
#   (using a glob with wildcards) and the corresponding aging/expiry periods
#   that should apply.
#
# The tool is engineered to be highly resilient. Once the configuration file is
# processed, any ephemeral disappearance of configured directories, or changes
# to the purge recipes (including syntax errors) or other exceptions during
# processing should get caught and handled with relevant warnings, pauses, and
# retries. Each purge loop "starts over from fresh" in the sense that it
# re-enters the configured directory path to scan for purge recipes, so if the
# original directory is renamed and a new one is created, the purge tool won't
# stay stuck in the old, renamed one.
#
### JSON formats:
#
# In the documentation below, JSON format and structure will be described in a
# way that uses "#"-comments. So taken literally they are not valid JSON, they
# are used as a liberty simply for documentation purposes.
#
### Purge recipes:
#
# An individual purge recipe combines a glob (filesystem path with wildcards)
# with an expiry period. The glob is literally a field called "glob" that
# should match on all files that might need purging. The expiry period is
# specified by one or more integer-valued fields ("years", "months", "weeks",
# "days", "hours", "minutes", and "seconds" are all accepted) that additively
# specify the "age" at which files matching the glob should be purged. (The age
# of a file is determined by its 'mtime' attribute.)
#
# Purge recipes are represented in JSON as either a single struct, or as an
# array of structs (when specifying multiple recipes in one). Each struct is
# formatted like the following;
#    {
#        # This field's value is consumed by the python "glob.glob()" API
#        "glob": "/home/roleaccount_foo/debug-*",
#        # These fields combine to specify that matching files should be
#        # purged once their modification timestamps are 2.5 hours old.
#        "hours": 2,
#        "minutes": 30
#    }
#
### Start-up configuration:
#
# The text representation of the startup configuration (in JSON) should be set
# in the HCP_PURGER_JSON environment variable, or should it be passed as the
# first argument to the command-line. It takes the following format;
#    {
#        # The location where purge recipes get scanned for
#        "dir": "/path/to/state",
#        # When the tool is running without error, this is the delay between
#        # purge loops (in seconds)
#        "period": 20,
#        # After an error, this is the delay before retrying (in seconds)
#        "retry": 60,
#        # The purger itself produces very detailed logs about its processing.
#        # This is the directory where those logs get produced to;
#        "purgerlogdir": "/purger/logs",
#        # This is a python "format"-string that presumes the existence of an
#        # python object, "t", of type datetime.timedelta. This example shows
#        # the purger rotating to a new log file every hour.
#        "purgerlogfmt": "{t.year:04}{t.month:02}{t.day:02}{t.hour:02}",
#        # A static purge recipe (or array of recipes) can be provided here at
#        # configuration-time, that will always be considered (first!) in each
#        # purge loop. Here we use that to eat our own dog-food, ie. by purging
#        # the log files written by this tool.
#        "purgerlogjson": {
#            "glob": "/purger/logs/*",
#            "hours": 5
#        }
#    }

import os
import sys
import time
from datetime import datetime, timezone, timedelta
import glob
import json

sys.path.insert(1, '/hcp/common')
from hcp_common import bail, dict_timedelta, dict_val_or, hcp_config_extract

print("Running purger task")

# Pull our entire conf, we'll examine its fields directly. (We could call
# hcp_config_extract for each attribute, but we don't.)
conf = hcp_config_extract('.purger', must_exist = True)

def log(s):
	global conf 
	conf['currentlog'].write(f"{s}\n")
	conf['currentlog'].flush()

def log_and_stderr(s):
	print(f"{s}", file = sys.stderr)
	log(f"{s}")

def newlog(now, conf):
	newID = conf['purgerlogfmt'].format(t = now)
	if newID != conf['currentlogID']:
		try:
			nl = open(f"{conf['purgerlogdir']}/{newID}", "a")
			conf['currentlog'] = nl
			log(f"# Previous log ID: {conf['currentlogID']}")
			log(f"#      New log ID: {newID}")
			conf['currentlogID'] = newID
		except BaseException as e:
			conf['currentlog'] = sys.stderr
			log(f"Failed to open logfile: {e}")
			raise e

# This function acts on a single, parsed JSON descriptor. Called from
# do_purge().
def do_purge_item(j, now, conf):
	log(f"Recipe: {j}")
	g = j['glob']
	td = dict_timedelta(j)
	if now + td == now:
		bail("Non-zero time period must be provided to purger")
	cutoff = now - td
	log(f"timedelta={td}")
	files = glob.glob(g)
	log(f"Considering files\n - glob={g}\n - files=[{files}]")
	for f in files:
		s = os.stat(f)
		log(f"Considering file:\n - file={f}\n - mtime={s.st_mtime}")
		dt = datetime.fromtimestamp(s.st_mtime, timezone.utc)
		if dt < cutoff:
			log(" - Delete")
			os.remove(f)
		else:
			log(" - Keep")

def do_purge_item_wrapper(j, now, conf):
	if isinstance(j, list):
		for i in j:
			do_purge_item(i, now, conf)
	elif isinstance(j, dict):
		do_purge_item(j, now, conf)
	else:
		bail(f"Purge recipe not a dict or a list: {j}")

# Run a single purge loop;
# - refresh the output we log to. (We direct our exceptions there too.)
# - "enter" the purger directory fresh from the path (e.g. so we can handle
#   directories getting renamed and replaced).
# - act on each JSON descriptor one by one.
def do_purge(conf):
	now = datetime.now(timezone.utc)
	newlog(now, conf)
	os.chdir('/')
	os.chdir(conf['dir'])
	purgees = glob.glob("*.json")
	log(f"Purge loop\n - now={now}\n - recipes={purgees}")
	log(f"Processing built-in recipe(s)")
	do_purge_item_wrapper(conf['purgerlogjson'], now, conf)
	for p in purgees:
		log(f"Processing recipe file: {p}")
		with open(p, "r") as f:
			j = json.load(f)
		do_purge_item_wrapper(j, now, conf)

# The main function
# - normalize the conf
# - eat our own dogfood (rotate logfiles and make them subject to purging)
def do_main():
	global conf
	# 'dir'
	if 'dir' not in conf:
		bail(f"No 'dir' attribute specified in configuration")
	if not os.path.isdir(conf['dir']):
		os.mkdir(conf['dir'])
	# 'period' and 'retry'
	conf['period'] = dict_val_or(conf, 'period', 60)
	conf['retry'] = dict_val_or(conf, 'retry', 300)
	# 'purgerlogdir'
	conf['purgerlogdir'] = dict_val_or(conf, 'purgerlogdir',
					f"{conf['dir']}/logs-purger")
	if not os.path.isdir(conf['purgerlogdir']):
		os.mkdir(conf['purgerlogdir'])
	# 'purgerlogfmt'
	conf['purgerlogfmt'] = dict_val_or(conf, 'purgerlogfmt',
		"{t.year:04}{t.month:02}{t.day:02}{t.hour:02}")
	# 'purgerlogjson'
	conf['purgerlogjson'] = dict_val_or(conf, 'purgerlogjson',
		{
			'glob': f"{conf['purgerlogdir']}/*",
			'days': 1,
		})
	# 'currentlog'
	conf['currentlog'] = sys.stderr
	conf['currentlogID'] = ''
	# Main loop: handle any errors with resilience. (Hence the importance
	# of having log files...) Also, push these exceptions to the logs and
	# to stderr. The latter is what will likely trigger someone to go look
	# at the former.
	while True:
		try:
			do_purge(conf)
		except BaseException as e:
			log_and_stderr(f"Warn: swallowed exception: {e}")
			log_and_stderr(f"Sleeping for {conf['retry']} seconds before retrying")
			time.sleep(conf['retry'])
			log_and_stderr("Retrying...")
			continue
		time.sleep(conf['period'])

do_main()
