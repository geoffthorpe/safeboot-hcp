import flask
from flask import request, abort, send_file
import subprocess
import json
import os, sys
from stat import *
from markupsafe import escape
from werkzeug.utils import secure_filename
import tempfile

app = flask.Flask(__name__)
app.config["DEBUG"] = True


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
        form_profile = "default"
    else:
        form_profile = request.form['profile']
    if 'paramfile' not in request.files:
        form_paramfile = None
    else:
        form_paramfile = request.files['paramfile']
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
    if form_paramfile:
        local_paramfile = os.path.join(tf.name,
                                       secure_filename(form_paramfile.filename))
        form_paramfile.save(local_paramfile)
    opadd_args = sudoargs + ['/hcp/enrollsvc/op_add.sh',
                             local_ekpub, form_hostname, form_profile]
    if form_paramfile:
        opadd_args += [local_paramfile]
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
    form_ekpubhash = request.args['ekpubhash']
    c = subprocess.run(sudoargs + ['/hcp/enrollsvc/op_query.sh',
                                   form_ekpubhash],
                       stdout=subprocess.PIPE, stderr = subprocess.PIPE,
                       text=True)
    print(c.stdout)
    if c.returncode != 0:
        print("Failed operation, dumping stderr")
        print(c.stderr, file = sys.stderr)
        abort(500)
    j = json.loads(c.stdout)
    return j

@app.route('/v1/delete', methods=['POST'])
def my_delete():
    form_ekpubhash = request.form['ekpubhash']
    c = subprocess.run(sudoargs + ['/hcp/enrollsvc/op_delete.sh',
                                   form_ekpubhash],
                       stdout=subprocess.PIPE, stderr = subprocess.PIPE,
                       text=True)
    print(c.stdout)
    if (c.returncode != 0):
        print("Failed operation, dumping stderr")
        print(c.stderr, file = sys.stderr)
        abort(500)
    j = json.loads(c.stdout)
    return j

@app.route('/v1/find', methods=['GET'])
def my_find():
    form_hostname_suffix = request.args['hostname_suffix']
    c = subprocess.run(sudoargs + ['/hcp/enrollsvc/op_find.sh',
                                   form_hostname_suffix],
                       stdout=subprocess.PIPE, stderr = subprocess.PIPE,
                       text=True)
    print(c.stdout)
    if (c.returncode != 0):
        print("Failed operation, dumping stderr")
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
