# vim: set expandtab shiftwidth=4 softtabstop=4:
import flask
from flask import request, abort, send_file, make_response
import subprocess
import json
import os, sys
from stat import *
from markupsafe import escape
from werkzeug.utils import secure_filename
import tempfile
import requests

sys.path.insert(1, '/hcp/common')
from hcp_common import log, current_tracefile, http2exit, exit2http

sys.path.insert(1, '/hcp/xtra')
from HcpRecursiveUnion import union
from HcpPemHelper import get_email_address

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
    log(f"get_request_data({uri})")
    request_data = {
        'uri': uri
    }
    # Curate a copy of the request environment that only contains non-empty,
    # string-valued variables.
    e = { x: request.environ[x] for x in request.environ if
             type(request.environ[x]) is str and len(request.environ[x]) > 0 }
    if 'SSL_CLIENT_CERT' in e:
        s = e['SSL_CLIENT_CERT']
        log(f"SSL_CLIENT_CERT={s}")
        email = get_email_address(s)
        log(f"email={email}")
        auth = {}
        auth['client_cert'] = s
        if email:
            auth['email'] = email
        request_data['auth'] = auth
    return request_data

@app.route('/', methods=['GET'])
def home():
    def addcmd(url, heading, button, isPost = True, checkbox = None):
        if isPost:
            txtMethod = 'method="post" enctype="multipart/form-data"'
        else:
            txtMethod = 'method="get"'
        if checkbox:
            cbox = '''
<tr><td>{name}</td><td><input type=checkbox name={name}></td>
    <td>Optional</td></tr>
'''.format(name = checkbox)
        else:
            cbox = ''
        return '''
<h2>{xheading};</h2>
<form {xtxtMethod} action="{xurl}">
<table>
<tr><td>principals</td><td><input type=text name=principals></td>
    <td>JSON array, don't include the trailing "@REALM".<br>
    Eg. ["alicia/admin", "host/server.domain.com"]</td></tr>
<tr><td>profile</td><td><input type=text name=profile></td>
    <td>JSON struct requesting specific options</td></tr>
{xcbox}
</table>
<input type="submit" value="{xbutton}">
</form>
'''.format(xheading = heading, xtxtMethod = txtMethod,
            xurl = url, xbutton = button, xcbox = cbox)
    return '''
<h1>KDC Service Management API</h1>
<hr>
{c_add}
{c_add_ns}
{c_get}
{c_del}
{c_del_ns}
{c_ext_keytab}
'''.format(c_add = addcmd("/v1/add",
                            "To add (regular) principals",
                            "Create principals"),
            c_add_ns = addcmd("/v1/add_ns",
                            "To add (virtual) namespace principals",
                            "Create namespace principals"),
            c_get = addcmd("/v1/get",
                            "To query principals",
                            "Query",
                            isPost = False,
                            checkbox = "verbose"),
            c_del = addcmd("/v1/del",
                            "To delete (regular) principals",
                            "Delete"),
            c_del_ns = addcmd("/v1/del_ns",
                            "To delete (virtual) namespace principals",
                            "Delete NS"),
            c_ext_keytab = addcmd("/v1/ext_keytab", "To export principals to a keytab",
                            "Export keytab"))

@app.route('/healthcheck', methods=['GET'])
def healthcheck():
    return '''
<h1>Healthcheck</h1>
'''

# We enforce privilege separation by running this flask app as the flask_user
# account, which has no direct access to any KDC state. A sudo rule allows
# flask_user to invoke the /hcp/kdcsvc/do_kadmin.sh script running as 'root'.
# The primary role of that script is to perform argument-validation, to
# mitigate the risk of a compromised flask app. (The sudo configuration ensures
# a fresh environment across this call interface, preventing a compromised
# flask handler from influencing the script other than by the arguments passed
# to the command.) Arguments passed to 'do_kadmin.sh' are;
# $1 - name of the requested operation ("add", "add_ns", "ext_keytab", etc),
# $2 - list of principals (a JSON array),
# $3 - any command-specific options/attributes (a JSON struct).
#
# This is the sudo preamble to pass to subprocess.run(), the actual operation
# string ("add", "query", etc) and arguments follow this, and are appended by
# each handler.
sudoargs = [ 'sudo', '--', '/hcp/kdcsvc/do_kadmin.py' ]

# The exit code from the sudo's process is expected to be the http status code,
# rather than the more conventional unix approach where 0 is success and
# anything else is an error code. To be safe, we sanity-check the status code
# before allowing it to be used, and we handle construction of the response.
def check_status_code(c, mylog):
    mylog(f"check_status_code: returncode={c.returncode}")
    httpcode = exit2http(c.returncode)
    mylog(f"check_status_code: httpcode={httpcode}")
    # We accept success in the 2xx form ...
    if httpcode >= 200 and httpcode < 300:
        try:
            j = json.loads(c.stdout)
        except json.JSONDecodeError as e:
            mylog(f"JSON decoding error, line={e.lineno}, col={e.colno}, msg={e.msg}\n" +
                "--- document to JSONDecode ---\n" +
                f"{e.doc}" +
                "--- document to JSONDecode ---")
            return make_response("Error: server JSON error", 500)
    # ... or failure in any other form
    else:
        mylog(f"aborting")
        return make_response(f"Error", httpcode)
    mylog(f"decoded from stdout: {j}")
    resp = make_response(json.dumps(j), httpcode)
    resp.headers['Content-Type'] = 'application/json'
    return resp

def my_json_loads(x, t, mylog):
    try:
        r = json.loads(x)
    except json.JSONDecodeError as e:
        mylog(f"Error, {t} doesn't contain valid JSON;\n{x}")
        abort(http2exit(400))
    return r

# Many handlers have the same parameter-processing (and sudo-command-forming)
# needs, so this function factors out that commonality.
def my_cmd_handler(url, cmd, request, isPost = True):
    def mylog(s):
        log(f"{cmd},{url}: {s}")
    mylog(f"starting\nrequest={request}")
    mylog(f"request.form={request.form}")
    mylog(f"request.args={request.args}")
    if isPost:
        mylog("POST, using 'form'")
        args = request.form
    else:
        mylog("GET, using 'args'")
        args = request.args
    form_principals = "[]"
    if 'principals' in args and len(args['principals']) > 0:
        form_principals = args['principals']
    mylog(f"form_principals={form_principals}")
    _ = my_json_loads(form_principals, 'principals', mylog)
    form_profile="{}"
    if 'profile' in args and len(args['profile']) > 0:
        form_profile = args['profile']
    mylog(f"form_profile={form_profile}")
    form_data = my_json_loads(form_profile, 'profile', mylog)
    if 'verbose' in args:
        form_data['verbose'] = 1
    request_data = get_request_data(url)
    request_data = union(form_data, request_data)
    request_json = json.dumps(request_data)
    op_args = sudoargs + [ cmd, form_principals, request_json]
    mylog(f"args={op_args}")
    c = subprocess.run(op_args,
                       stdout = subprocess.PIPE,
                       stderr = current_tracefile,
                       text = True)
    return check_status_code(c, mylog)

@app.route('/v1/add', methods=['POST'])
def my_add():
    return my_cmd_handler('/v1/add', 'add', request)

@app.route('/v1/add_ns', methods=['POST'])
def my_add_ns():
    return my_cmd_handler('/v1/add_ns', 'add_ns', request)

@app.route('/v1/get', methods=['GET'])
def my_get():
    return my_cmd_handler('/v1/get', 'get', request, isPost = False)

@app.route('/v1/del', methods=['POST'])
def my_del():
    return my_cmd_handler('/v1/del', 'del', request)

@app.route('/v1/del_ns', methods=['POST'])
def my_del_ns():
    return my_cmd_handler('/v1/del_ns', 'del_ns', request)

@app.route('/v1/ext_keytab', methods=['POST'])
def my_ext_keytab():
    return my_cmd_handler('/v1/ext_keytab', 'ext_keytab', request)

if __name__ == "__main__":
    app.run()
