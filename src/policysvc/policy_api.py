# vim: set expandtab shiftwidth=4 softtabstop=4:
import flask
from flask import request, abort, send_file
import subprocess
import json
import os, sys
from stat import *
from markupsafe import escape
from werkzeug.utils import secure_filename
import tempfile
import requests

sys.path.insert(1, '/hcp/common')
from hcp_tracefile import tracefile
tfile = tracefile("policysvc")
sys.stderr = tfile
from hcp_common import log

sys.path.insert(1, '/hcp/xtra')
import HcpJsonPolicy

app = flask.Flask(__name__)
app.config["DEBUG"] = False

# Load, via env-var, a JSON input that policy checkers can consult. Note, each
# policy check request will carry its own '__env' settings that need to be
# applied to the policy (ie. parameter expansion), and this can't happen after
# we've converted the JSON to a python object. So we carry around the JSON
# string and let each invocation expand it before parsing it.
policyjson = {}
if 'HCP_POLICYSVC_JSON' in os.environ:
    policyjsonpath = os.environ['HCP_POLICYSVC_JSON']
    policyjson = open(policyjsonpath, "r").read()

# There is also a bail() in hcp_common.py, but it is generic and doesn't use
# the flask-specific abort() to control the http status code.
def bail(val, msg=None):
    if not msg:
        msg = "Unclarified error"
    print(f"FAIL:{val}: {msg}", file=sys.stderr)
    abort(val, msg)

@app.route('/healthcheck', methods=['GET'])
def healthcheck():
    return '''
<h1>Healthcheck</h1>
'''

@app.route('/run', methods=['POST'])
def my_common():
    log(f"my_common: request.form={request.form}")
    params = {}
    if 'params' in request.form:
        try:
            params = json.loads(request.form['params'])
        except ValueError:
            bail(401, "Policy check: malformed 'params'")

    # Before passing the request "params" through the policy filters, take the
    # extra information and embed it. This implies that the parameters cannot
    # have fields conflicting with any of these.
    if 'hookname' in request.form:
        hookname = request.form['hookname']
        params['hookname'] = hookname
    if 'request_uid' in request.form:
        request_uid = request.form['request_uid']
        params['request_uid'] = request_uid

    # Both the policy and the input data need to be in string (JSON)
    # representation. The policy already is, but params is a struct.
    paramsjson = json.dumps(params)
    policy_result = HcpJsonPolicy.run_with_env(policyjson, paramsjson,
                                                 includeEnv=True)
    if policy_result['action'] != "accept":
        print(f"REJECT: {paramsjson} -> {policy_result}")
        bail(403, "Policy check: blocked by filter rules")

    # Success. Write something to the log that is not completely useless.
    print(f"ALLOW: {paramsjson} -> {policy_result}")
    return params

if __name__ == "__main__":
    app.run()
