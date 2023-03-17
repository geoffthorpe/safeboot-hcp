HCP_TESTCREDS_OUT := $(HCP_OUT)/testcreds

$(HCP_TESTCREDS_OUT): | $(HCP_OUT)
MDIRS += $(HCP_TESTCREDS_OUT)

HCP_TESTCREDS_DOCKER_RUN := \
	docker run -i --rm --init --label $(HCP_IMAGE_PREFIX)all=1 \
	--mount type=bind,source=$(HCP_TESTCREDS_OUT),destination=/testcreds \
	--mount type=bind,source=$(HCP_SRC)/reffile,destination=/reffile,readonly \
	--env HCP_NO_CONFIG=1 \
	--entrypoint="" \
	$(call HCP_IMAGE,caboodle) \
	bash -c

CMD_CREDS_CHOWN := /chowner.sh /reffile/reffile .

# "enrollsigner" This signs enrollments so that attesting clients can verify
# them. Note that this is not acting as a credential issuer, e.g. if an
# enrollment produces signed certificates then they are signed by something
# else (likely "enrollcertissuer", see below). Once the enrolled assets are
# produced however, this key will sign them so that the client can verify that
# they haven't been modified. (This allows us to worry less about 'attestsvc'
# and replication.)
HCP_TESTCREDS_ENROLLSIGNER := $(HCP_TESTCREDS_OUT)/enrollsigner
$(HCP_TESTCREDS_ENROLLSIGNER): | $(HCP_TESTCREDS_OUT)
MDIRS += $(HCP_TESTCREDS_ENROLLSIGNER)
CMD_CREDS_ENROLLSIG := cd /testcreds/enrollsigner &&
CMD_CREDS_ENROLLSIG += openssl genrsa -out key.priv &&
CMD_CREDS_ENROLLSIG += openssl rsa -pubout -in key.priv -out key.pem &&
CMD_CREDS_ENROLLSIG += $(CMD_CREDS_CHOWN)
$(HCP_TESTCREDS_OUT)/done.enrollsigner: | $(HCP_TESTCREDS_ENROLLSIGNER)
$(HCP_TESTCREDS_OUT)/done.enrollsigner:
	$Q$(HCP_TESTCREDS_DOCKER_RUN) "$(CMD_CREDS_ENROLLSIG)"
	$Qtouch $@
HCP_TESTCREDS_DONE += $(HCP_TESTCREDS_OUT)/done.enrollsigner

# "enrollverifier"
#    Simply the public half of "enrollsigner". For obvious reasons,
#    "enrollsigner" is only mounted/visible to the enrollsvc::mgmt server, but
#    this public key is needed wherever attestation clients run. (To validate
#    the enrollment data they receive post-attestation.)
HCP_TESTCREDS_ENROLLVERIFIER := $(HCP_TESTCREDS_OUT)/enrollverifier
$(HCP_TESTCREDS_ENROLLVERIFIER): | $(HCP_TESTCREDS_OUT)
MDIRS += $(HCP_TESTCREDS_ENROLLVERIFIER)
$(HCP_TESTCREDS_OUT)/done.enrollverifier: | $(HCP_TESTCREDS_ENROLLVERIFIER)
$(HCP_TESTCREDS_OUT)/done.enrollverifier: $(HCP_TESTCREDS_OUT)/done.enrollsigner
$(HCP_TESTCREDS_OUT)/done.enrollverifier:
	$Qcp "$(HCP_TESTCREDS_ENROLLSIGNER)/key.pem" "$(HCP_TESTCREDS_ENROLLVERIFIER)/"
	$Qtouch $@
HCP_TESTCREDS_DONE += $(HCP_TESTCREDS_OUT)/done.enrollverifier

# "enrollcertissuer"
#    This is the HCP CA. The public half (the certificate) gets included in all
#    host enrollments (as "certissuer.pem") so that attesting clients can
#    install it as a trust root, thereby allowing them to validate credentials
#    of all hosts using HCP-issued credentials.
HCP_TESTCREDS_ENROLLCERTISSUER := $(HCP_TESTCREDS_OUT)/enrollcertissuer
$(HCP_TESTCREDS_ENROLLCERTISSUER): | $(HCP_TESTCREDS_OUT)
MDIRS += $(HCP_TESTCREDS_ENROLLCERTISSUER)
CMD_CREDS_ENROLLCERTISSUER := cd /testcreds/enrollcertissuer &&
CMD_CREDS_ENROLLCERTISSUER += source /hcp/common/hcp.sh &&
CMD_CREDS_ENROLLCERTISSUER += hxtool issue-certificate \
			--self-signed --issue-ca --generate-key=rsa \
			--subject="CN=CA,DC=hcphacking,DC=xyz" \
			--lifetime=10years \
			--certificate="FILE:CA.pem" &&
CMD_CREDS_ENROLLCERTISSUER += openssl x509 \
			-in CA.pem -outform PEM -out "CA.cert" &&
CMD_CREDS_ENROLLCERTISSUER += $(CMD_CREDS_CHOWN)
$(HCP_TESTCREDS_OUT)/done.enrollcertissuer: | $(HCP_TESTCREDS_ENROLLCERTISSUER)
$(HCP_TESTCREDS_OUT)/done.enrollcertissuer:
	$Q$(HCP_TESTCREDS_DOCKER_RUN) "$(CMD_CREDS_ENROLLCERTISSUER)"
	$Qtouch $@
HCP_TESTCREDS_DONE += $(HCP_TESTCREDS_OUT)/done.enrollcertissuer

# "enrollcertchecker"
#    Simply the public half of "enrollcertissuer". Most hosts get this via
#    attestation as it's included in their enrollments ("certissuer.pem") and
#    installed by the attestation client.
HCP_TESTCREDS_ENROLLCERTCHECKER := $(HCP_TESTCREDS_OUT)/enrollcertchecker
$(HCP_TESTCREDS_ENROLLCERTCHECKER): | $(HCP_TESTCREDS_OUT)
MDIRS += $(HCP_TESTCREDS_ENROLLCERTCHECKER)
$(HCP_TESTCREDS_OUT)/done.enrollcertchecker: | $(HCP_TESTCREDS_ENROLLCERTCHECKER)
$(HCP_TESTCREDS_OUT)/done.enrollcertchecker: $(HCP_TESTCREDS_OUT)/done.enrollcertissuer
$(HCP_TESTCREDS_OUT)/done.enrollcertchecker:
	$Qcp "$(HCP_TESTCREDS_ENROLLCERTISSUER)/CA.cert" "$(HCP_TESTCREDS_ENROLLCERTCHECKER)/"
	$Qtouch $@
HCP_TESTCREDS_DONE += $(HCP_TESTCREDS_OUT)/done.enrollcertchecker

# "enrollserver"
#    This is a web server certificate that can be used to host the
#    enrollsvc::mgmt API and serve enrollments. This is to avoid the
#    chicken-and-egg problems you otherwise get when running a
#    dev/debug/non-production use-case. We used to solve this by having
#    enrollsvc enroll _itself_, without starting the HTTPS interface, then wait
#    for the enrollment to replicate and attest to get its web-server
#    certificate. This worked but was more likely to confuse than inform any
#    innocent bystanders.
HCP_TESTCREDS_ENROLLSERVER := $(HCP_TESTCREDS_OUT)/enrollserver
$(HCP_TESTCREDS_ENROLLSERVER): | $(HCP_TESTCREDS_OUT)
MDIRS += $(HCP_TESTCREDS_ENROLLSERVER)
CMD_CREDS_ENROLLSERVER := cd /testcreds/enrollserver &&
CMD_CREDS_ENROLLSERVER += source /hcp/common/hcp.sh &&
CMD_CREDS_ENROLLSERVER += hxtool issue-certificate \
			--ca-certificate="FILE:/testcreds/enrollcertissuer/CA.pem" \
			--type=https-server \
			--hostname=emgmt.hcphacking.xyz \
			--generate-key=rsa --key-bits=2048 \
			--certificate="FILE:server.pem" && \
			$(CMD_CREDS_CHOWN)
$(HCP_TESTCREDS_OUT)/done.enrollserver: | $(HCP_TESTCREDS_ENROLLSERVER)
$(HCP_TESTCREDS_OUT)/done.enrollserver: $(HCP_TESTCREDS_OUT)/done.enrollcertissuer
$(HCP_TESTCREDS_OUT)/done.enrollserver:
	$Q$(HCP_TESTCREDS_DOCKER_RUN) "$(CMD_CREDS_ENROLLSERVER)"
	$Qtouch $@
HCP_TESTCREDS_DONE += $(HCP_TESTCREDS_OUT)/done.enrollserver

# "enrollclient"
#    This is a client certificate that can be used with the orchestration
#    client to hit the enrollsvc::mgmt API and request enrollments. This is to
#    avoid the chicken-and-egg problem you otherwise get when running a
#    dev/debug/non-production use-case;
#    Q: When an orchestrator uses the enrollsvc API via HTTPS, how does it
#       validate the web server certificate?
#    A: Easy, it is signed by "enrollcertissuer", so the the client just needs
#       to install that as a trust-root.
#    Q: Well how does the client do that?
#    A: Easy, by running attestation.
#    Q: When can it run attestation?
#    A: Easy, once an orchestration client has enrolled it (via HTTPS)...
#    ... that's where the chicken crawls back into the egg.
#    Solution: we run the orchestrator without assuming an environment that has
#    been attested and provisioned by HCP. We precreate this 'enrollclient'
#    cert without using enrollsvc, and the orchestration client will use this
#    and "enrollcertissuer" to talk HTTPS to enrollsvc.
HCP_TESTCREDS_ENROLLCLIENT := $(HCP_TESTCREDS_OUT)/enrollclient
$(HCP_TESTCREDS_ENROLLCLIENT): | $(HCP_TESTCREDS_OUT)
MDIRS += $(HCP_TESTCREDS_ENROLLCLIENT)
CMD_CREDS_ENROLLCLIENT := cd /testcreds/enrollclient &&
CMD_CREDS_ENROLLCLIENT += source /hcp/common/hcp.sh &&
CMD_CREDS_ENROLLCLIENT += hxtool issue-certificate \
			--ca-certificate="FILE:/testcreds/enrollcertissuer/CA.pem" \
			--type=https-client \
			--hostname=orchestrator.hcphacking.xyz \
			--subject="UID=orchestrator,DC=hcphacking,DC=xyz" \
			--email="orchestrator@hcphacking.xyz" \
			--generate-key=rsa --key-bits=2048 \
			--certificate="FILE:client.pem" && \
			$(CMD_CREDS_CHOWN)
$(HCP_TESTCREDS_OUT)/done.enrollclient: | $(HCP_TESTCREDS_ENROLLCLIENT)
$(HCP_TESTCREDS_OUT)/done.enrollclient: $(HCP_TESTCREDS_OUT)/done.enrollcertissuer
$(HCP_TESTCREDS_OUT)/done.enrollclient:
	$Q$(HCP_TESTCREDS_DOCKER_RUN) "$(CMD_CREDS_ENROLLCLIENT)"
	$Qtouch $@
HCP_TESTCREDS_DONE += $(HCP_TESTCREDS_OUT)/done.enrollclient

# A wrapper target to package testcreds
testcreds: $(HCP_TESTCREDS_DONE)
ALL += $(HCP_TESTCREDS_DONE)

# Cleanup
ifneq (,$(wildcard $(HCP_TESTCREDS_OUT)))
clean_testcreds:
	$Qrm -rf $(HCP_TESTCREDS_ENROLLCERTISSUER)
	$Qrm -rf $(HCP_TESTCREDS_ENROLLCERTCHECKER)
	$Qrm -rf $(HCP_TESTCREDS_ENROLLSIGNER)
	$Qrm -rf $(HCP_TESTCREDS_ENROLLVERIFIER)
	$Qrm -rf $(HCP_TESTCREDS_ENROLLSERVER)
	$Qrm -rf $(HCP_TESTCREDS_ENROLLCLIENT)
	$Qrm -f $(HCP_TESTCREDS_DONE)
	$Qrmdir $(HCP_TESTCREDS_OUT)
# Cleanup ordering
clean: clean_testcreds
endif
