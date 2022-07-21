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

app = flask.Flask(__name__)
app.config["DEBUG"] = False

@app.route('/healthcheck', methods=['GET'])
def healthcheck():
    return '''
<h1>Healthcheck</h1>
'''

# Our policy hook is simply going to permit everything so long as the request
# is well-formed, and will log the relevant details so the operator can watch.
# The idea is not to make this implementation configurable, the idea is to
# allow someone to implement their own policy endpoint.

# Wrapper around abort() that also logs
def bail(val, msg=None):
    if not msg:
        msg = "Unclarified error"
    print(f"FAIL:{val}: {msg}")
    abort(val, msg)

# Common processing for all URIs
def my_emgmt(uri):
    if 'hookname' not in request.form:
        bail(401, "Policy check::egmt:: no 'hookname'")
    hookname = request.form['hookname']
    params = None
    if 'params' in request.form:
        try:
            params = json.loads(request.form['params'])
        except ValueError:
            bail(401, "Policy check::egmt:: malformed 'params'")
    if 'auth' in request.form:
        try:
            auth = json.loads(request.form['auth'])
        except ValueError:
            bail(401, "Policy check::egmt:: malformed 'auth'")

    if hookname != 'enrollsvc::mgmt::client_check':
        bail(401, f"Policy check::egmt:: unrecognized hookname: {hookname}")

    # Success. Write something to the log that is not completely useless.
    # Exception: /healthcheck gets hit continuously and it's best left silent.
    if uri != '/healthcheck':
        print(f"ALLOW: emgmt::{uri}")
    return {
        "policy_endpoint": "enrollsvc::mgmt::client_check",
        "hookname": hookname,
        "uri": uri,
        "params": params,
        "auth": auth
    }

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
@app.route(f"/emgmt/v1/get-asset-signer", methods=['POST'])
def handler7():
    return my_emgmt('/v1/get-asset-signer')

if __name__ == "__main__":
    app.run()
