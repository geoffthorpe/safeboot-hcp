from flask import request

# enrollsvc::mgmt::client_check
#
# This hook is called by all enrollsvc mgmt API handlers.  If HTTPS has been
# properly configured, then the client will have already authenticated via a
# client-cert, and the server will have validated that the cert was signed by
# the appropriate CA. But that would still allow a client to use _any_
# certificate signed by that CA, whereas we want to restrict access to this API
# to only those should be (un)enrolling hosts.
#
# To put it more simply. The web server takes care of authn, but this is where
# _you_ can implement the authz you want.
#
# The reference example below implements these rules;
#  - if no client-cert has been processed, reject.
#  - for /healthcheck, accept, and don't log this case.
#  - if the client cert is "orchestrator", accept.
#  - otherwise, reject.

def enrollsvc_mgmt_client_check(uri):
    result = False
    client_dn = ''
    if 'SSL_CLIENT_S_DN' in request.environ:
        if uri == '/healthcheck':
            return True
        client_dn = request.environ['SSL_CLIENT_S_DN']
        if client_dn == 'UID=orchestrator,DC=hcphacking,DC=xyz':
            result = True
    if result:
        R = 'ALLOW'
    else:
        R = 'BLOCK'
    print(f'{R} enrollsvc::mgmt::client_check, (uri={uri},CLIENT_DN={client_dn})')
    return result
