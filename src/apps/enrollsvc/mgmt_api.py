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

# We want to work with environment in such a way that an empty env-var is
# treated like an absent env-var. Why? Here's what happens. A low level config
# file either sets LOWLEVEL_FOO to a value or comments it out to leave it
# undefined. In this way we can switch between alternative low-level configs. A
# uniform high level config then sets "HIGHLEVEL_FOO=$LOWLEVEL_FOO", inheriting
# whichever lower-level choices were made. However, this means HIGHLEVEL_FOO is
# always "set", though the value is empty when LOWLEVEL_FOO is undefined. This
# function takes an environment dict (e.g. 'os.environ' or 'request.environ')
# and returns a modified dict containing only the key-value pairs which had
# non-empty values.
def env_purity(env):
    result = {}
    for k in env:
        v = env[k]
        if type(v) is not str:
            continue
        if len(v) > 0:
            result[k] = v
    return result
pure_env = env_purity(os.environ)

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
    e = env_purity(request.environ)
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

<h2>To find host entries by hostname suffix;</h2>
<form method="get" action="/v1/find">
<table>
<tr><td>hostname suffix</td><td><input type=text name=hostname_suffix></td></tr>
</table>
<input type="submit" value="Find">
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
# account, which has no direct access to any enrollment state. Specific sudo
# rules allow flask_user to invoke the 4 /hcp/enrollsvc/op_<verb>.sh
# scripts (for <verb> in "add", "query", "delete", and "find") running as
# 'db_user'. The latter is the account that created the enrollment DB for use
# only by itself.  The primary role of the /hcp/enrollsvc/op_<verb>.sh scripts
# is to perform argument-validation, to mitigate the risk of a compromised
# flask app. (The sudo configuration ensures a fresh environment across this
# call interface, preventing a compromised flask handler from influencing the
# scripts other than by the arguments passed to the command.)
#
# This is the sudo preamble to pass to subprocess.run(), the actual script name
# and arguments follow this, and are appended by each handler.
db_user=os.environ['HCP_ENROLLSVC_USER_DB']
sudoargs=['sudo','-u',db_user]

@app.route('/v1/add', methods=['POST'])
def my_add():
    if 'ekpub' not in request.files:
        return { "error": "ekpub not in request" }
    if 'hostname' not in request.form:
        return { "error": "hostname not in request" }
    form_ekpub = request.files['ekpub']
    form_hostname = request.form['hostname']
    if 'profile' not in request.form:
        form_profile = "{}"
    else:
        form_profile = request.form['profile']
    request_data = get_request_data('/v1/add')
    request_data['params'] = form_profile
    request_json = json.dumps(request_data)
    # Create a temporary directory (for the ek.pub file), and make it world
    # readable+executable. The /hcp/enrollsvc/op_add.sh script runs behind
    # sudo, as another user, and it needs to be able to read the ek.pub.
    tf = tempfile.TemporaryDirectory()
    s = os.stat(tf.name)
    os.chmod(tf.name, s.st_mode | S_IROTH | S_IXOTH)
    # Sanitize the user-supplied filename, and join it to the temp directory,
    # this is where the ek.pub file gets saved and is the path passed to the
    # op_add.sh script.
    local_ekpub = os.path.join(tf.name,
                               secure_filename(form_ekpub.filename))
    form_ekpub.save(local_ekpub)
    opadd_args = sudoargs + ['/hcp/enrollsvc/op_add.sh',
                             local_ekpub, form_hostname, request_json]
    c = subprocess.run(opadd_args,
                       stdout = subprocess.PIPE, stderr = subprocess.PIPE,
                       text = True)
    if c.returncode != 0:
        # stderr is for debugging
        # stdout is for the user (hint: don't leak sensitive info to stdout!)
        print("Failed operation, dumping stderr")
        print(c.stderr, file = sys.stderr)
        return {
            "returncode": c.returncode,
            "txt": c.stdout
        }
    j = json.loads(c.stdout)
    return j

@app.route('/v1/query', methods=['GET'])
def my_query():
    if 'ekpubhash' not in request.args:
        return { "error": "ekpubhash not in request" }
    request_data = get_request_data('/v1/query')
    request_data['params'] = {
        'ekpubhash': request.args['ekpubhash']
    }
    request_json = json.dumps(request_data)
    c = subprocess.run(sudoargs + ['/hcp/enrollsvc/op_query.sh', request_json],
                       stdout=subprocess.PIPE, stderr = subprocess.PIPE,
                       text=True)
    if c.returncode != 0:
        print("Failed operation, dumping stdout+stderr")
        print(c.stdout, file = sys.stderr)
        print(c.stderr, file = sys.stderr)
        abort(500)
    j = json.loads(c.stdout)
    return j

@app.route('/v1/delete', methods=['POST'])
def my_delete():
    if 'ekpubhash' not in request.args:
        return { "error": "ekpubhash not in request" }
    request_data = get_request_data('/v1/delete')
    request_data['params'] = {
        'ekpubhash': request.form['ekpubhash']
    }
    request_json = json.dumps(request_data)
    c = subprocess.run(sudoargs + ['/hcp/enrollsvc/op_delete.sh', request_json],
                       stdout=subprocess.PIPE, stderr = subprocess.PIPE,
                       text=True)
    if (c.returncode != 0):
        print("Failed operation, dumping stdout+stderr")
        print(c.stdout, file = sys.stderr)
        print(c.stderr, file = sys.stderr)
        abort(500)
    j = json.loads(c.stdout)
    return j

@app.route('/v1/find', methods=['GET'])
def my_find():
    if 'hostname_suffix' not in request.args:
        return { "error": "hostname_suffix not in request" }
    request_data = get_request_data('/v1/find')
    request_data['params'] = {
        'hostname_suffix': request.args['hostname_suffix']
    }
    request_json = json.dumps(request_data)
    c = subprocess.run(sudoargs + ['/hcp/enrollsvc/op_find.sh', request_json],
                       stdout=subprocess.PIPE, stderr = subprocess.PIPE,
                       text=True)
    if (c.returncode != 0):
        print("Failed operation, dumping stdout+stderr")
        print(c.stdout, file = sys.stderr)
        print(c.stderr, file = sys.stderr)
        abort(500)
    j = json.loads(c.stdout)
    return j

@app.route('/v1/get-asset-signer', methods=['GET'])
def assetSigner():
    return send_file('/signer/key.pem',
                     as_attachment = True,
                     attachment_filename = 'asset-signer.pem')

if __name__ == "__main__":
    app.run()
