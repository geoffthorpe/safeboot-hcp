# vim: set expandtab shiftwidth=4 softtabstop=4:
import flask
from flask import request, abort, send_file, jsonify
import subprocess
import json
import os, sys
from stat import *
from markupsafe import escape
from werkzeug.utils import secure_filename
import tempfile
import requests

sys.path.insert(1, '/hcp/common')
from hcp_common import log, bail, hcp_config_extract

sys.path.insert(1, '/hcp/xtra')
import HcpJsonPolicy

app = flask.Flask(__name__)
app.config["DEBUG"] = False

# The policysvc is implemented via 'webapi', where the '.webapi.app' property
# (ie. the flask app) is /hcp/policysvc/policy_api.py. In that case, we pull
# the policy JSON path from '.webapi.config'.
policyjsonpath = hcp_config_extract('.webapi.config', must_exist = True)
policyjson = open(policyjsonpath, "r").read()

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
            return "Bad JSON input", 401

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
    policy_result = HcpJsonPolicy.run(policyjson, params, dataKeepsVars = True)
    if policy_result['action'] != "accept":
        print(f"REJECT: {paramsjson} -> {policy_result}")
        return "Blocked by policy", 403

    # Success. Write something to the log that is not completely useless.
    print(f"ALLOW: {paramsjson} -> {policy_result}")
    return jsonify(params)

if __name__ == "__main__":
    app.run()
