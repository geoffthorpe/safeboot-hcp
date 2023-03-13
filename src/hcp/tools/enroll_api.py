#!/usr/bin/python3
# vim: set expandtab shiftwidth=4 softtabstop=4:

# A crude way to perform these tasks directly (using curl) is;
#
# add:     curl -v -F ekpub=@</path/to/ek.pub> \
#               -F hostname=<hostname> \
#               -F profile=<profile> \
#               <enrollsvc-URL>/v1/add
#
# query:   curl -v -G -d ekpubhash=<hexstring> \
#               <enrollsvc-URL>/v1/query
#
# delete:  curl -v -F ekpubhash=<hexstring> \
#               <enrollsvc-URL>/v1/delete
#
# reenroll: curl -v -F ekpubhash=<hexstring> \
#               <enrollsvc-URL>/v1/reenroll
#
# find:    curl -v -G -d hostname_regex=<hostname_regex> \
#               <enrollsvc-URL>/v1/find
#
# janitor: curl -v -G <enrollsvc-URL>/v1/janitor
#
# get-asset-signer:  curl -v -G <enrollsvc-URL>/v1/get-asset-signer

import json
import requests
import os
import sys
import argparse
import time

loglevel = 0
def set_loglevel(v):
    global loglevel
    loglevel = v

def _log(level, s):
    if level <= loglevel:
        print(f"{s}", file = sys.stderr)
def err(s):
    _log(0, s)
def log(s):
    _log(1, s)
def debug(s):
    _log(2, s)

auth = None
if os.environ.get('HCP_GSSAPI'):
    log('Enabling GSSAPI authentication')
    try:
        from requests_gssapi import HTTPSPNEGOAuth, DISABLED
        auth = HTTPSPNEGOAuth(mutual_authentication=DISABLED, opportunistic_auth=True)
    except ModuleNotFoundError:
        log("'requests-gssapi' unavailable, falling back to 'requests-kerberos'")
        try:
            from requests_kerberos import HTTPKerberosAuth, DISABLED
            auth = HTTPKerberosAuth(mutual_authentication=DISABLED, force_preemptive=True)
        except ModuleNotFoundError:
            log("'requests-kerberos' unavailable, falling back to no authentication")

# TODO: make this interface more import-friendly and less cmd-line-specific.
# I.e. the enroll_*() functions tag an 'args' structure for all parameters,
# direct from the argparse output. Should probably add an intermediate layer to
# unpack those and pass the parameters into a more API-like interface for the
# actual implementations.

# This internal function is used as a wrapper to deal with exceptions and
# retries. 'args' specifies whether retries' should be attempted and how many
# times, how long to pause between those retries, etc. 'request_fn' is a
# caller-supplied callback (eg. lambda) function that performs the desired
# operation and (if no exception occurs) returns the desired result.  This
# caller-supplied function typically calls requests.get() or requests.post()
# with whatever inputs are desired and passes back the return value from that.
# Note, the retries are only considered in the case that an exception was
# thrown in the 'request_fn'. If 'request_fn' returns without exception, we
# pass along whatever it returned rather than retrying. (If the response
# contains a non-2xx http status code, that's not our business.)
        #except requests.exceptions.RequestException as e:
def requester_loop(args, request_fn):
    debug(f"requester_loop: retries={args.retries}, pause={args.pause}")
    retries = args.retries
    while True:
        try:
            debug("requester_loop: calling request_fn()")
            response = request_fn()
        except Exception as e:
            if retries > 0:
                debug(f"requester_loop: caught exception, retries={retries}")
                debug(f" - e: {e}")
                retries -= 1
                time.sleep(args.pause)
                continue
            debug(f"requester_loop: caught exception, no retries")
            debug(f" - e: {e}")
            raise e
        debug("requester_loop: returning")
        return response

# Handler functions for the subcommands (add, query, delete, find)
# They all return a 2-tuple of {result,json}, where result is True iff the
# operation was successful.

def enroll_add(args):
    form_data = {
        'ekpub': ('ek.pub', open(args.ekpub, 'rb')),
        'hostname': (None, args.hostname)
    }
    if args.profile is not None:
        form_data['profile'] = (None, args.profile)
    debug("'add' handler about to call API")
    debug(f" - url: {args.api + '/v1/add'}")
    debug(f" - files: {form_data}")
    myrequest = lambda: requests.post(args.api + '/v1/add',
                             files=form_data,
                             auth=auth,
                             verify=args.requests_verify,
                             cert=args.requests_cert,
                             timeout=args.timeout)
    response = requester_loop(args, myrequest)
    debug(f" - response: {response}")
    debug(f" - response.content: {response.content}")
    if response.status_code != 201:
        err(f"Error, 'add' response status code was {response.status_code}")
        return False, None
    try:
        jr = json.loads(response.content)
    except Exception as e:
        err(f"Error, JSON decoding of 'add' response failed: {e}")
        return False, None
    debug(f" - jr: {jr}")
    return True, jr

def enroll_reenroll(args):
    form_data = { 'ekpubhash': (None, args.ekpubhash) }
    debug("'reenroll' handler about to call API")
    debug(f" - url: {args.api + '/v1/reenroll'}")
    debug(f" - files: {form_data}")
    myrequest = lambda: requests.post(args.api + '/v1/reenroll',
                             files=form_data,
                             auth=auth,
                             verify=args.requests_verify,
                             cert=args.requests_cert,
                             timeout=args.timeout)
    response = requester_loop(args, myrequest)
    debug(f" - response: {response}")
    debug(f" - response.content: {response.content}")
    if response.status_code != 201:
        err(f"Error, 'reenroll' response status code was {response.status_code}")
        return False, None
    try:
        jr = json.loads(response.content)
    except Exception as e:
        err(f"Error, JSON decoding of 'add' response failed: {e}")
        return False, None
    debug(f" - jr: {jr}")
    return True, jr

def do_query_or_delete(args, is_delete):
    if is_delete:
        form_data = { 'ekpubhash': (None, args.ekpubhash) }
        if args.nofiles:
            form_data['nofiles'] = (None, True)
        debug("'delete' handler about to call API")
        debug(f" - url: {args.api + '/v1/delete'}")
        debug(f" - files: {form_data}")
        myrequest = lambda: requests.post(args.api + '/v1/delete',
                                 files=form_data,
                                 auth=auth,
                                 verify=args.requests_verify,
                                 cert=args.requests_cert,
                                 timeout=args.timeout)
        response = requester_loop(args, myrequest)
    else:
        form_data = { 'ekpubhash': args.ekpubhash }
        if args.nofiles:
            form_data['nofiles'] = True
        debug("'query' handler about to call API")
        debug(f" - url: {args.api + '/v1/query'}")
        debug(f" - files: {form_data}")
        myrequest = lambda: requests.get(args.api + '/v1/query',
                                params=form_data,
                                auth=auth,
                                verify=args.requests_verify,
                                cert=args.requests_cert,
                                timeout=args.timeout)
        response = requester_loop(args, myrequest)
    debug(f" - response: {response}")
    debug(f" - response.content: {response.content}")
    if response.status_code != 200:
        err(f"Error, response status code was {response.status_code}")
        return False, None
    try:
        jr = json.loads(response.content)
    except Exception as e:
        log(f"Error, JSON decoding of response failed: {e}")
        return False, None
    debug(f" - jr: {jr}")
    return True, jr

def enroll_query(args):
    return do_query_or_delete(args, False)

def enroll_delete(args):
    return do_query_or_delete(args, True)

def enroll_find(args):
    form_data = { 'hostname_regex': args.hostname_regex }
    debug("'find' handler about to call API")
    debug(f" - url: {args.api + '/v1/find'}")
    debug(f" - files: {form_data}")
    myrequest = lambda: requests.get(args.api + '/v1/find',
                            params=form_data,
                            auth=auth,
                            verify=args.requests_verify,
                            cert=args.requests_cert,
                            timeout=args.timeout)
    response = requester_loop(args, myrequest)
    debug(f" - response: {response}")
    debug(f" - response.content: {response.content}")
    if response.status_code != 200:
        log(f"Error, 'find' response status code was {response.status_code}")
        return False, None
    try:
        jr = json.loads(response.content)
    except Exception as e:
        log("Error, JSON decoding of 'find' response failed: {e}")
        return False, None
    debug(f" - jr: {jr}")
    return True, jr

def enroll_janitor(args):
    debug("'janitor' handler about to call API")
    debug(f" - url: {args.api + '/v1/janitor'}")
    myrequest = lambda: requests.get(args.api + '/v1/janitor',
                            auth=auth,
                            verify=args.requests_verify,
                            cert=args.requests_cert,
                            timeout=args.timeout)
    response = requester_loop(args, myrequest)
    debug(f" - response: {response}")
    debug(f" - response.content: {response.content}")
    if response.status_code != 200:
        log(f"Error, 'janitor' response status code was {response.status_code}")
        return False, None
    try:
        jr = json.loads(response.content)
    except Exception as e:
        log("Error, JSON decoding of 'janitor' response failed: {e}")
        return False, None
    debug(f" - jr: {jr}")
    return True, jr

def enroll_getAssetSigner(args):
    debug("'getAssetSigner' handler about to call API")
    debug(f" - url: {args.api + '/v1/get-asset-signer'}")
    myrequest = lambda: requests.get(args.api + '/v1/get-asset-signer',
                            auth=auth,
                            verify=args.requests_verify,
                            cert=args.requests_cert,
                            timeout=args.timeout)
    response = requester_loop(args, myrequest)
    debug(f" - response: {response}")
    debug(f" - response.content: {response.content}")
    if response.status_code != 200:
        log(f"Error, 'getAssetSigner' response status code was {response.status_code}")
        return False, None
    if args.output:
        debug(" - output: {args.output}")
        open(args.output, 'wb').write(response.content)
    else:
        debug(" - output: stdout")
        sys.stdout.buffer.write(response.content)
    return True, None

if __name__ == '__main__':

    # Wrapper 'enroll' command, using argparse

    enroll_desc = 'API client for Enrollment Service management interface'
    enroll_epilog = """
    If the URL for the Enrollment Service's management API is not supplied on the
    command line (via '--api'), it will fallback to using the 'ENROLLSVC_API_URL'
    environment variable. If the API is using HTTPS and the server certificate is
    not signed by a CA that is already trusted by the system, '--cacert' should
    be used to specify a CA certificate (or bundle) that should be considered
    trusted. (Otherwise, specify '--noverify' to inhibit certificate validation.)
    To use a client certificate to authenticate to the server, specify
    '--clientcert'. If that file doesn't include the private key, specify it with
    '--clientkey'.

    To see subcommand-specific help, pass '-h' to the subcommand.
    """
    enroll_help_api = 'base URL for management interface'
    enroll_help_cacert = 'path to CA cert (or bundle) for validating server certificate'
    enroll_help_noverify = 'disable validation of server certificate'
    enroll_help_verbosity = 'verbosity level, 0 means quiet, more than 0 means less quiet'
    enroll_help_clientcert = 'path to client cert to authenticate with'
    enroll_help_clientkey = 'path to client key (if not included with --clientcert)'
    enroll_help_retries = 'max number of API retries'
    enroll_help_pause = 'number of seconds between retries'
    enroll_help_timeout = 'number of seconds to allow before giving up'
    parser = argparse.ArgumentParser(description=enroll_desc,
                                     epilog=enroll_epilog)
    parser.add_argument('--api', metavar='<URL>',
                        default=os.environ.get('ENROLLSVC_API_URL'),
                        help=enroll_help_api)
    parser.add_argument('--cacert', metavar='<PATH>',
                        default=os.environ.get('ENROLLSVC_API_CACERT'),
                        help=enroll_help_cacert)
    parser.add_argument('--noverify', action='store_true',
                        help=enroll_help_noverify)
    parser.add_argument('--clientcert', metavar='<PATH>',
                        default=os.environ.get('ENROLLSVC_API_CLIENTCERT'),
                        help=enroll_help_clientcert)
    parser.add_argument('--clientkey', metavar='<PATH>',
                        default=os.environ.get('ENROLLSVC_API_CLIENTKEY'),
                        help=enroll_help_clientkey)
    parser.add_argument('--verbosity', type=int, metavar='<level>',
                        default=0, help=enroll_help_verbosity)
    parser.add_argument('--retries', type=int, metavar='<num>',
                        default=0, help=enroll_help_retries)
    parser.add_argument('--pause', type=int, metavar='<secs>',
                        default=0, help=enroll_help_pause)
    parser.add_argument('--timeout', type=int, metavar='<secs>',
                        default=600, help=enroll_help_timeout)

    subparsers = parser.add_subparsers()

    # Subcommand details

    add_help = 'Enroll a {TPM,hostname} 2-tuple'
    add_epilog = """
    The 'add' subcommand invokes the '/v1/add' handler of the Enrollment Service's
    management API, to trigger the enrollment of a TPM+hostname 2-tuple. The
    provided 'ekpub' file should be either in the PEM format (text) or TPM2B_PUBLIC
    (binary). The provided hostname is registered in the TPM enrollment in order to
    create a binding between the TPM and its corresponding host - this should not be
    confused with the '--api' argument, which provides a URL to the Enrollment
    Service! Control over the enrollment, including the set of assets desired and
    configuration for it, is passed as a JSON string via the --profile argument.
    """
    add_help_ekpub = 'path to the public key file for the TPM\'s Endorsement Key'
    add_help_hostname = 'hostname to be enrolled with (and bound to) the TPM'
    add_help_profile = 'enrollment profile to use (optional)'
    parser_a = subparsers.add_parser('add', help=add_help, epilog=add_epilog)
    parser_a.add_argument('ekpub', help=add_help_ekpub)
    parser_a.add_argument('hostname', help=add_help_hostname)
    parser_a.add_argument('--profile', help=add_help_profile, required=False)
    parser_a.set_defaults(func=enroll_add)

    reenroll_help = 'Re-enroll a TPM/host based on hash(EKpub)'
    reenroll_epilog = """
    The 'reenroll' subcommand invokes the '/v1/reenroll' handler of the Enrollment
    Service's management API, to reenroll an existing enrollment.
    """
    reenroll_help_ekpubhash = 'hexidecimal "ekpubhash" of the TPM'
    parser_d = subparsers.add_parser('reenroll', help=reenroll_help, epilog=reenroll_epilog)
    parser_d.add_argument('ekpubhash', help=reenroll_help_ekpubhash)
    parser_d.set_defaults(func=enroll_reenroll)

    query_help = 'Query (and list) enrollments based on prefix-search of hash(EKpub)'
    query_epilog = """
    The 'query' subcommand invokes the '/v1/query' handler of the Enrollment
    Service's management API, to retrieve an array of enrollment entries matching
    the query criteria. Enrollment entries are indexed by 'ekpubhash', which is a
    hash of the public half of the TPM's Endorsement Key. The query parameter is a
    hexidecimal string, which is used as a prefix search for the query. Passing an
    empty string will return all enrolled entries in the database, or by providing 1
    or 2 hexidecimal characters approximately 1/16th or 1/256th of the enrolled
    entries (respectively) will be returned. To query a specific entry, the query
    parameter should contain enough of the ekpubhash to uniquely distinguish it from
    all others. (Usually, this is significantly fewer characters than the full
    ekpubhash value.)
    """
    query_help_ekpubhash = 'hexidecimal prefix (empty to return all enrollments)'
    query_help_nofiles = 'do not return file listings, just hostname and ekpubhash'
    parser_q = subparsers.add_parser('query', help=query_help, epilog=query_epilog)
    parser_q.add_argument('ekpubhash', help=query_help_ekpubhash)
    parser_q.add_argument('--nofiles', action='store_true', help=query_help_nofiles)
    parser_q.set_defaults(func=enroll_query)

    delete_help = 'Delete enrollments based on prefix-search of hash(EKpub)'
    delete_epilog = """
    The 'delete' subcommand invokes the '/v1/delete' handler of the Enrollment
    Service's management API, to delete (and retrieve) an array of enrollment
    entries matching the query criteria. The 'delete' subcommand supports precisely
    the same parameterisation as 'query', so please consult the 'query' help for
    more detail. Both commands return an array of enrollment entries that match the
    query parameter. The only distinction is that the 'delete' command,
    unsurprisingly, will also delete the matching enrollment entries.
    """
    delete_help_ekpubhash = 'hexidecimal prefix (empty to delete all enrollments)'
    parser_d = subparsers.add_parser('delete', help=delete_help, epilog=delete_epilog)
    parser_d.add_argument('ekpubhash', help=delete_help_ekpubhash)
    parser_d.add_argument('--nofiles', action='store_true', help=query_help_nofiles)
    parser_d.set_defaults(func=enroll_delete)

    find_help = 'Find enrollments based on regex-search for hostname'
    find_epilog = """
    The 'find' subcommand invokes the '/v1/find' handler of the Enrollment Service's
    management API, to retrieve an array of enrollment entries whose hostnames match
    the given regular expression. Unlike 'query' which searches based on the hash of
    the TPM's EK public key, 'find' looks at the hostname each TPM is enrolled for.
    Note, the array returned from this command consists of solely of 'ekpubhash'
    values for matching enrollments. To obtain details about the matching entries
    (including the hostnames that matched), subsequent API calls (using 'query')
    should be performed using the 'ekpubhash' fields.
    """
    find_help_regex = 'hostname regular expression'
    parser_f = subparsers.add_parser('find', help=find_help, epilog=find_epilog)
    parser_f.add_argument('hostname_regex', help=find_help_regex)
    parser_f.set_defaults(func=enroll_find)

    janitor_help = 'Scrub the enrollment DB to fix known issues, and rebuild hn2ek'
    janitor_epilog = """
    The 'janitor' subcommand invokes the '/v1/janitor' handler of the Enrollment
    Service's management API, to clean up known glitches that may be present in the
    enrollment DB (usually created by enrollment bugs
    that have since been fixed). It also rebuilds the reverse-lookup table, hn2ek,
    from first principles.
    """
    parser_j = subparsers.add_parser('janitor', help=janitor_help, epilog=janitor_epilog)
    parser_j.set_defaults(func=enroll_janitor)

    getAssetSigner_help = 'Retrieve trust anchor for asset-signing'
    getAssetSigner_epilog = """
    The 'getAssetSigner' subcommand invokes the '/v1/getAssetSigner' handler of
    the Enrollment Service's management API, to download the trust anchor to
    allow an attestation client to validate the signatures on its enrolled
    assets.
    """
    getAssetSigner_help_output = 'path to the save the trust anchor to'
    parser_g = subparsers.add_parser('getAssetSigner', help=getAssetSigner_help,
                                     epilog=getAssetSigner_epilog)
    parser_g.add_argument('--output', metavar='<PATH>',
                          default = None,
                          help=getAssetSigner_help_output)
    parser_g.set_defaults(func=enroll_getAssetSigner)

    # Process the command-line
    args = parser.parse_args()
    set_loglevel(args.verbosity)
    log(f"verbosity={args.verbosity}")
    if not args.api:
        err("Error, no API URL was provided.")
        sys.exit(-1)
    if args.noverify:
        args.requests_verify = False
    elif args.cacert:
        args.requests_verify = args.cacert
    else:
        args.requests_verify = True
    if args.clientcert:
        if args.clientkey:
            args.requests_cert = (args.clientcert,args.clientkey)
        else:
            args.requests_cert = args.clientcert
    else:
        args.requests_cert = False

    # Dispatch. Here, we are operating as a program with a parent process, not a library with
    # a caller. If we don't catch exceptions, they get handled by the runtime which will print
    # stack traces to stderr and exit, there is no concept of the exceptions reaching the
    # parent process. As such, catch them all here.
    try:
        result, j = args.func(args)
    except Exception as e:
        print(f"Error, unable to hit API end-point: {e}", file = sys.stderr)
        sys.exit(-1)
    log(f"handler returned: result={result},j={j}")
    if j:
        print(json.dumps(j))
    if not result:
        sys.exit(-1)
