#!/bin/bash

source /hcp/common/hcp.sh

# This healthcheck relies on attestation to provide the 'user2' pkinit-client
# certificate, as well as availability of the (secondary) KDC. (Because kinit
# uses the former to get a TGT from the latter.)

kinit -C FILE:/etc/ssl/hostcerts/hostcert-pkinit-user-user2-key.pem user2 klist

