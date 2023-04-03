# vim: set expandtab shiftwidth=4 softtabstop=4:
import flask
from flask import request, abort, send_file, Response, make_response
import subprocess
import json
import os, sys
from stat import *
from markupsafe import escape
from werkzeug.utils import secure_filename
import tempfile
import requests

sys.path.insert(1, '/hcp/common')
from hcp_common import log, exit2http, current_tracefile

sys.path.insert(1, '/hcp/xtra')
from HcpRecursiveUnion import union

sys.path.insert(1, '/hcp/enrollsvc')
import db_common

app = flask.Flask(__name__)
app.config["DEBUG"] = False

# Prepare the "request" object that lower-level calls (running behind the sudo
# curtain) can use when making policy lookups. The caller of this function will
# take the structure as the return value, add a 'params' of its own to the
# structure, convert it to a JSON string, and then pass it as an argument to
# the sudo'd command.
# The structure includes;
#  - the uri of the originating request
#  - any details from the HTTPS request (client authentication) that we can
#    pass through.
def get_request_data(uri):
    request_data = {
        'uri': uri,
        'auth': {}
    }
    # Curate a copy of the request environment that only contains non-empty,
    # string-valued variables.
    e = { x: request.environ[x] for x in request.environ if
             type(request.environ[x]) is str and len(request.environ[x]) > 0 }
    if 'SSL_CLIENT_CERT' in e:
        request_data['auth']['client_cert'] = e['SSL_CLIENT_CERT']
    return request_data

@app.route('/', methods=['GET'])
def home():
    return '''
<h1>Enrollment Service Management API</h1>
<hr>

<h2>To add a new host entry;</h2>
<form method="post" enctype="multipart/form-data" action="/v1/add">
<table>
<tr><td>ekpub</td><td><input type=file name=ekpub></td></tr>
<tr><td>hostname</td><td><input type=text name=hostname></td></tr>
<tr><td>profile</td><td><input type=text name=profile></td></tr>
<tr><td>paramfile</td><td><input type=file name=paramfile></td></tr>
</table>
<input type="submit" value="Enroll">
</form>

<h2>To query host entries;</h2>
<form method="get" action="/v1/query">
<table>
<tr><td>ekpubhash prefix</td><td><input type=text name=ekpubhash></td></tr>
</table>
<input type="submit" value="Query">
</form>

<h2>To delete host entries;</h2>
<form method="post" action="/v1/delete">
<table>
<tr><td>ekpubhash prefix</td><td><input type=text name=ekpubhash></td></tr>
</table>
<input type="submit" value="Delete">
</form>

<h2>To reenroll a host entry;</h2>
<form method="post" action="/v1/reenroll">
<table>
<tr><td>ekpubhash</td><td><input type=text name=ekpubhash></td></tr>
</table>
<input type="submit" value="Reenroll">
</form>

<h2>To find host entries by hostname regex;</h2>
<form method="get" action="/v1/find">
<table>
<tr><td>hostname regex</td><td><input type=text name=hostname_regex></td></tr>
</table>
<input type="submit" value="Find">
</form>

<h2>To trigger the janitor (looks for known issues, regenerates the
hn2ek table, etc);</h2>
<form method="get" action="/v1/janitor">
<input type="submit" value="Janitor">
</form>

<h2>To retrieve the asset-signing trust anchor;</h2>
<a href="/v1/get-asset-signer">Click here</a>
'''
@app.route('/healthcheck', methods=['GET'])
def healthcheck():
    return '''
<h1>Healthcheck</h1>
'''

# We enforce privilege separation by running this flask app as the flask_user
# account, which has no direct access to any enrollment state. A sudo rule
# allows flask_user to invoke the /hcp/enrollsvc/mgmt_sudo.sh script running as
# 'db_user'. The latter is the account that created the enrollment DB for use
# only by itself. The primary role of the /hcp/enrollsvc/mgmt_sudo.sh script is
# to perform argument-validation, to mitigate the risk of a compromised flask
# app. (The sudo configuration ensures a fresh environment across this call
# interface, preventing a compromised flask handler from influencing the
# scripts other than by the arguments passed to the command.) The first
# argument passed to 'mgmt_sudo.sh' is the name of the requested operation
# ("add", "query", "delete", "find" are currently-supported), which it uses to
# validate that the number of arguments being passed and then directs execution
# to the corresponding python script.
#
# This is the sudo preamble to pass to subprocess.run(), the actual operation
# string ("add", "query", etc) and arguments follow this, and are appended by
# each handler.
db_user = db_common.dbuser
sudoargs = [ 'sudo', '-u', db_user, '/hcp/enrollsvc/mgmt_sudo.sh' ]

# The exit code from the sudo's process is expected to be the http status code,
# rather than the more conventional unix approach where 0 is success and
# anything else is an error code. To be safe, we sanity-check the status code
# before allowing it to be used, and we handle construction of the response.
def check_status_code(c):
    log(f"check_status_code: returncode={c.returncode}")
    httpcode = exit2http(c.returncode)
    log(f"check_status_code: httpcode={httpcode}")
    # We accept success in the 2xx form ...
    if httpcode >= 200 and httpcode < 300:
        try:
            j = json.loads(c.stdout)
        except json.JSONDecodeError as e:
            log(f"JSON decoding error, line={e.lineno}, col={e.colno}, msg={e.msg}")
            log("--- document to JSONDecode ---")
            log(f"{e.doc}")
            log("--- document to JSONDecode ---")
            return ("Server JSON error", 500)
    # ... or failure in any other form
    else:
        log(f"aborting")
        return make_response("Error", httpcode)
    log(f"decoded from stdout: {j}")
    resp = make_response(json.dumps(j), httpcode)
    resp.headers['Content-Type'] = 'application/json'
    return resp

@app.route('/v1/add', methods=['POST'])
def my_add():
    log(f"my_add: request={request}")
    if 'ekpub' not in request.files:
        return make_response("Error: ekpub not in request", 400)
    if 'hostname' not in request.form:
        return make_response("Error: hostname not in request", 400)
    form_ekpub = request.files['ekpub']
    form_hostname = request.form['hostname']
    form_profile = "{}"
    if 'profile' in request.form:
        tmpprofile = request.form['profile']
        if len(tmpprofile) > 0:
            form_profile = tmpprofile
    log(f"my_add: form_profile={form_profile}")
    form_data = json.loads(form_profile)
    request_data = get_request_data('/v1/add')
    request_data = union(form_data, request_data)
    request_json = json.dumps(request_data)
    # Create a temporary directory (for the ek.pub file), and make it world
    # readable+executable. The /hcp/enrollsvc/db_add.py script runs behind
    # sudo, as another user, and it needs to be able to read the ek.pub.
    tf = tempfile.TemporaryDirectory()
    s = os.stat(tf.name)
    os.chmod(tf.name, s.st_mode | S_IROTH | S_IXOTH)
    # Sanitize the user-supplied filename, and join it to the temp directory,
    # this is where the ek.pub file gets saved and is the path passed to the
    # db_add.sh script.
    local_ekpub = os.path.join(tf.name,
                               secure_filename(form_ekpub.filename))
    form_ekpub.save(local_ekpub)
    opadd_args = sudoargs + [ 'add', local_ekpub, form_hostname, request_json]
    log(f"my_add: opadd_args={opadd_args}")
    c = subprocess.run(opadd_args,
                       stdout = subprocess.PIPE,
                       stderr = current_tracefile,
                       text = True)
    foo = check_status_code(c)
    return foo

@app.route('/v1/query', methods=['GET'])
def my_query():
    log(f"my_query: request={request}")
    if 'ekpubhash' not in request.args:
        return make_response("Error: ekpubhash not in request", 400)
    request_data = get_request_data('/v1/query')
    request_data['ekpubhash'] = request.args['ekpubhash']
    if 'nofiles' in request.args:
        request_data['nofiles'] = True
    else:
        request_data['nofiles'] = False
    request_json = json.dumps(request_data)
    log(f"my_query: request_json={request_json}")
    c = subprocess.run(sudoargs + [ 'query', request_json ],
                       stdout = subprocess.PIPE,
                       stderr = current_tracefile,
                       text = True)
    return check_status_code(c)

@app.route('/v1/delete', methods=['POST'])
def my_delete():
    log(f"my_delete: request={request}")
    if 'ekpubhash' not in request.form:
        return make_response("Error: ekpubhash not in request", 400)
    request_data = get_request_data('/v1/delete')
    request_data['ekpubhash'] = request.form['ekpubhash']
    if 'nofiles' in request.form:
        request_data['nofiles'] = True
    else:
        request_data['nofiles'] = False
    request_json = json.dumps(request_data)
    log(f"my_delete: request_json={request_json}")
    c = subprocess.run(sudoargs + [ 'delete', request_json ],
                       stdout=subprocess.PIPE, stderr = subprocess.PIPE,
                       text=True)
    return check_status_code(c)

@app.route('/v1/reenroll', methods=['POST'])
def my_reenroll():
    log(f"my_reenroll: request={request}")
    if 'ekpubhash' not in request.form:
        return make_response("Error: ekpubhash not in request", 400)
    request_data = get_request_data('/v1/reenroll')
    request_data['ekpubhash'] = request.form['ekpubhash']
    request_json = json.dumps(request_data)
    log(f"my_reenroll: request_json={request_json}")
    c = subprocess.run(sudoargs + [ 'reenroll', request_json ],
                       stdout=subprocess.PIPE, stderr = subprocess.PIPE,
                       text=True)
    return check_status_code(c)

@app.route('/v1/find', methods=['GET'])
def my_find():
    log(f"my_find: request={request}")
    if 'hostname_regex' not in request.args:
        return make_response("Error: hostname_regex not in request", 400)
    request_data = get_request_data('/v1/find')
    request_data['hostname_regex'] = request.args['hostname_regex']
    request_json = json.dumps(request_data)
    log(f"my_find: request_json={request_json}")
    c = subprocess.run(sudoargs + [ 'find', request_json],
                       stdout=subprocess.PIPE, stderr = subprocess.PIPE,
                       text=True)
    return check_status_code(c)

@app.route('/v1/janitor', methods=['GET'])
def my_janitor():
    log(f"my_janitor: request={request}")
    c = subprocess.run(sudoargs + [ 'janitor' ],
                       stdout=subprocess.PIPE,
                       text=True)
    return check_status_code(c)

@app.route('/v1/get-asset-signer', methods=['GET'])
def assetSigner():
    log(f"assetSigner: request={request}")
    log("assetSigner: /enrollsigner/key.pem")
    return send_file(f"/enrollsigner/key.pem",
                     as_attachment = True,
                     attachment_filename = 'asset-signer.pem')

if __name__ == "__main__":
    app.run()
