HCP_TESTCREDS_OUT := $(HCP_OUT)/testcreds

$(HCP_TESTCREDS_OUT): | $(HCP_OUT)
MDIRS += $(HCP_TESTCREDS_OUT)

# Note, we do _NOT_use HCP_BASE_DNAME for running our openssl commands, because
# there's a gotcha: one of the options for building HCP_BASE is that you can
# choose to have it inject (and trust) our "certissuer" test cred. So, circular
# dependency alert! We depend on an earlier stage image (HCP_BASE2_DNAME),
# prior to the stage where CA certs get embedded.
HCP_TESTCREDS_DOCKER_RUN := \
	docker run -i --rm --label $(HCP_IMAGE_PREFIX)all=1 \
	--mount type=bind,source=$(HCP_TESTCREDS_OUT),destination=/testcreds \
	$(HCP_BASE3_DNAME) \
	bash -c

# A pre-requisite for all assets is the "reference" file. This gets used as the
# "--reference" argument to chown commands, to ensure that all files created
# within the containers have the expected file-system ownership on the
# host-side. It also, encapsulates the dependencies on $(HCP_OUT) being created
# and the $(HCP_BASE_DNAME) image being built.
$(HCP_TESTCREDS_OUT)/reference: | $(HCP_OUT)
$(HCP_TESTCREDS_OUT)/reference: | $(HCP_BASE3_TOUCHFILE)
$(HCP_TESTCREDS_OUT)/reference:
	$Qecho "Unused file" > "$@"

CMD_CREDS_CHOWN := /hcp/base/chowner.sh /testcreds/reference .

# "enrollsigner"
HCP_TESTCREDS_ENROLLSIGNER := $(HCP_TESTCREDS_OUT)/enrollsigner
$(HCP_TESTCREDS_ENROLLSIGNER): | $(HCP_TESTCREDS_OUT)
MDIRS += $(HCP_TESTCREDS_ENROLLSIGNER)
CMD_CREDS_ENROLLSIG := cd /testcreds/enrollsigner &&
CMD_CREDS_ENROLLSIG += openssl genrsa -out key.priv &&
CMD_CREDS_ENROLLSIG += openssl rsa -pubout -in key.priv -out key.pem &&
CMD_CREDS_ENROLLSIG += $(CMD_CREDS_CHOWN)
$(HCP_TESTCREDS_OUT)/done.enrollsigner: | $(HCP_TESTCREDS_ENROLLSIGNER)
$(HCP_TESTCREDS_OUT)/done.enrollsigner: $(HCP_TESTCREDS_OUT)/reference
$(HCP_TESTCREDS_OUT)/done.enrollsigner:
	$Q$(HCP_TESTCREDS_DOCKER_RUN) "$(CMD_CREDS_ENROLLSIG)"
	$Qtouch $@
HCP_TESTCREDS_DONE += $(HCP_TESTCREDS_OUT)/done.enrollsigner

# "enrollverifier" - this is simply the public-only half of enrollsigner
HCP_TESTCREDS_ENROLLVERIFIER := $(HCP_TESTCREDS_OUT)/enrollverifier
$(HCP_TESTCREDS_ENROLLVERIFIER): | $(HCP_TESTCREDS_OUT)
MDIRS += $(HCP_TESTCREDS_ENROLLVERIFIER)
$(HCP_TESTCREDS_OUT)/done.enrollverifier: | $(HCP_TESTCREDS_ENROLLVERIFIER)
$(HCP_TESTCREDS_OUT)/done.enrollverifier: $(HCP_TESTCREDS_OUT)/done.enrollsigner
$(HCP_TESTCREDS_OUT)/done.enrollverifier:
	$Qcp $(HCP_TESTCREDS_ENROLLSIGNER)/key.pem $(HCP_TESTCREDS_ENROLLVERIFIER)/
	$Qtouch $@
HCP_TESTCREDS_DONE += $(HCP_TESTCREDS_OUT)/done.enrollverifier

# "enrollcertissuer"
HCP_TESTCREDS_ENROLLCERTISSUER := $(HCP_TESTCREDS_OUT)/enrollcertissuer
$(HCP_TESTCREDS_ENROLLCERTISSUER): | $(HCP_TESTCREDS_OUT)
MDIRS += $(HCP_TESTCREDS_ENROLLCERTISSUER)
CMD_CREDS_ENROLLCERTISSUER := cd /testcreds/enrollcertissuer &&
CMD_CREDS_ENROLLCERTISSUER += openssl genrsa -out CA.priv &&
CMD_CREDS_ENROLLCERTISSUER += openssl req -new -key CA.priv \
			-subj /CN=localhost -x509 -out CA.cert &&
CMD_CREDS_ENROLLCERTISSUER += $(CMD_CREDS_CHOWN)
$(HCP_TESTCREDS_OUT)/done.enrollcertissuer: | $(HCP_TESTCREDS_ENROLLCERTISSUER)
$(HCP_TESTCREDS_OUT)/done.enrollcertissuer: $(HCP_TESTCREDS_OUT)/reference
$(HCP_TESTCREDS_OUT)/done.enrollcertissuer:
	$Q$(HCP_TESTCREDS_DOCKER_RUN) "$(CMD_CREDS_ENROLLCERTISSUER)"
	$Qtouch $@
HCP_TESTCREDS_DONE += $(HCP_TESTCREDS_OUT)/done.enrollcertissuer

# Special handling, see settings.mk for why and src/base/Makefile for how.
# (Note, it would be preferable to put this rule in src/base, "where it
# belongs", but we can't - the TESTCRED definitions don't exist when that stuff
# gets processed.)
ifdef HCP_4ADD_CACERTS_ENABLE
ifdef HCP_4ADD_CACERTS_TESTCRED
$(HCP_BASE_4CA_OUT)/HCP_TESTCRED.cert: | $(HCP_BASE_4CA_OUT)
$(HCP_BASE_4CA_OUT)/HCP_TESTCRED.cert: $(HCP_TESTCREDS_OUT)/done.enrollcertissuer
	$Qcp $(HCP_TESTCREDS_OUT)/enrollcertissuer/CA.cert $@
endif
endif

# A wrapper target to package testcreds
testcreds: $(HCP_TESTCREDS_DONE)
ALL += testcreds

# Cleanup
ifneq (,$(wildcard $(HCP_TESTCREDS_OUT)))
clean_testcreds:
	$Qrm -f $(HCP_TESTCREDS_OUT)/reference
	$Qrm -rf $(HCP_TESTCREDS_ENROLLSIGNER)
	$Qrm -rf $(HCP_TESTCREDS_ENROLLCERTISSUER)
	$Qrm -rf $(HCP_TESTCREDS_ENROLLVERIFIER)
	$Qrm -f $(HCP_TESTCREDS_DONE)
	$Qrmdir $(HCP_TESTCREDS_OUT)
# Cleanup ordering
clean: clean_testcreds
endif
