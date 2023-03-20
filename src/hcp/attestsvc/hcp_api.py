# The 'sbin/attest-server' in safeboot already declares a flask app, called
# "app", and will run it using flask's built-in dev/debug server if executed
# directly. Here, we simply reuse that 'app' object and its API handlers, and
# we add our healthcheck handler. This gets loaded by uwsgi, in run_hcp.sh.

import sys

sys.path.insert(1, '/install-safeboot/sbin')
from attest_server import app

# Inject the healthcheck handler
@app.route('/healthcheck', methods=['GET'])
def hcp_healthcheck():
    return '''
<h1>Healthcheck</h1>
'''
