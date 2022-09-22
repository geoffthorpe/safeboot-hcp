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

@app.route('/healthcheck', methods=['GET'])
def healthcheck():
    return '''
<h1>Healthcheck</h1>
'''

# There is also a bail() in hcp_common.py, but it is generic and doesn't use
# the flask-specific abort() to control the http status code.
def bail(val, msg=None):
    if not msg:
        msg = "Unclarified error"
    print(f"FAIL:{val}: {msg}", file=sys.stderr)
    abort(val, msg)

# Common processing for all URIs
def my_common(uri, required_hookname):
    if 'hookname' not in request.form:
        bail(401, "Policy check::egmt:: no 'hookname'")
    hookname = request.form['hookname']
    if 'request_uid' not in request.form:
        bail(401, "Policy check::egmt:: no 'request_uid'")
    request_uid = request.form['request_uid']
    params = {}
    if 'params' in request.form:
        try:
            params = json.loads(request.form['params'])
        except ValueError:
            bail(401, "Policy check::egmt:: malformed 'params'")
    auth = {}
    if 'auth' in request.form:
        try:
            auth = json.loads(request.form['auth'])
        except ValueError:
            bail(401, "Policy check::egmt:: malformed 'auth'")

    if hookname != required_hookname:
        bail(401, f"Policy check::egmt:: unexpected hookname: {hookname}")

    # Before passing the request "params" through the policy filters, take the
    # extra information and embed it. This implies that the parameters cannot
    # have fields conflicting with any of these.
    params['uri'] = uri
    params['hookname'] = hookname
    params['request_uid'] = request_uid
    params['auth'] = auth

    # Both the policy and the input data need to be in string (JSON)
    # representation. The policy already is, but params is a struct.
    paramsjson = json.dumps(params)
    policy_result = HcpJsonPolicy.run_with_env(policyjson, paramsjson,
                                                 includeEnv=True)
    if policy_result['result'] != "accept":
        bail(403, f"REJECT:\n{json.dumps(params)}\n{json.dumps(policy_result)}")

    # Success. Write something to the log that is not completely useless.
    # Exception: /healthcheck gets hit continuously and it's best left silent.
    if uri != '/healthcheck':
        print(f"ALLOW: {json.dumps(params)}")
    return params

def my_emgmt(uri):
    return my_common(uri, 'enrollsvc::mgmt::client_check')
def my_genprog(uri):
    return my_common(uri, 'enrollsvc::mgmt::asset_check')

# Is there a way to generate the handlers from an array like this?
#     uri_list = [ '/', '/healthcheck',
#                  '/v1/add', '/v1/query', '/v1/delete',
#                  '/v1/find', '/v1/get-asset-signer' ]
#     for uri in uri_list:
#         @app.route(f"/emgmt{uri}", methods=['POST'])
#         def _():
#             return my_emgmt(uri)
#
# The problem is defining the decorated function. Calling it "_" doesn't get us
# around the problem, python complains about this as soon as the list has more
# than one item in it.

@app.route(f"/emgmt/", methods=['POST'])
def handler1():
    return my_emgmt('/')
@app.route(f"/emgmt/healthcheck", methods=['POST'])
def handler2():
    return my_emgmt('/healthcheck')
@app.route(f"/emgmt/v1/add", methods=['POST'])
def handler3():
    return my_emgmt('/v1/add')
@app.route(f"/emgmt/v1/query", methods=['POST'])
def handler4():
    return my_emgmt('/v1/query')
@app.route(f"/emgmt/v1/delete", methods=['POST'])
def handler5():
    return my_emgmt('/v1/delete')
@app.route(f"/emgmt/v1/find", methods=['POST'])
def handler6():
    return my_emgmt('/v1/find')
@app.route(f"/emgmt/v1/janitor", methods=['POST'])
def handler7():
    return my_emgmt('/v1/janitor')
@app.route(f"/emgmt/v1/get-asset-signer", methods=['POST'])
def handler8():
    return my_emgmt('/v1/get-asset-signer')

@app.route(f"/emgmt/gencert-hxtool", methods=['POST'])
def handler9():
    return my_genprog('gencert-hxtool')

if __name__ == "__main__":
    app.run()
