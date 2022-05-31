##############
# Versioning #
##############

HCP_VER_MAJOR := 1
HCP_VER_MINOR := 1
HCP_VER := $(HCP_VER_MAJOR):$(HCP_VER_MINOR)

#######################################
# Top-level control, defaults, config #
#######################################

TOP := $(shell pwd)
Q := $(if $(strip $V),,@)

include settings.mk

HCP_OUT ?= $(TOP)/output
HCP_SRC := $(TOP)/src
HCP_UTIL := $(TOP)/util

# $(HCP_OUT) is the only directory we explicitly create during preprocessing,
# rather than adding it to MDIRS and relying on order-only dependencies to
# create it. This is because preprocessing also creates a suite of hidden
# dependency files ("$(HCP_OUT)/.deps.<whatever>") and that can't rely on
# recipe-time directory-creation, per MDIRS.
ifeq (,$(wildcard $(HCP_OUT)))
$(info Creating HCP_OUT=$(HCP_OUT))
$(shell mkdir $(HCP_OUT))
endif

# Used in dependency chains, as a change in these files can have effects that
# require rebuilding other things.
ifndef HCP_RELAX
HCP_DEPS_COMMON := $(TOP)/Makefile $(TOP)/settings.mk
endif

###############
# Build logic #
###############

include src/Makefile

#########
# Tests #
#########

include tests/Makefile

######################################
# Environment for docker-compose.yml #
######################################

HCP_ORCHESTRATOR_JSON := $(TOP)/fleet.json
$(HCP_OUT)/docker-compose.env: | $(HCP_OUT)
$(HCP_OUT)/docker-compose.env: $(TOP)/settings.mk
$(HCP_OUT)/docker-compose.env: $(TOP)/Makefile
$(HCP_OUT)/docker-compose.env: $(HCP_SRC)/testcreds.Makefile
$(HCP_OUT)/docker-compose.env: $(HCP_APPS_SRC)/usecase/common.env
$(HCP_OUT)/docker-compose.env:
	$Qecho "Generating: docker-compose.env"
	$Qecho "## Autogenerated environment, used by docker-compose.yml" > $@
	$Qecho "" >> $@
	$Qecho "# Variables produced by the build environment;" >> $@
	$Qecho "HCP_IMAGE_COMMON=$(call HCP_IMAGE,common)" >> $@
	$Qecho "HCP_IMAGE_ENROLLSVC=$(call HCP_IMAGE,enrollsvc)" >> $@
	$Qecho "HCP_IMAGE_ATTESTSVC=$(call HCP_IMAGE,attestsvc)" >> $@
	$Qecho "HCP_IMAGE_SWTPMSVC=$(call HCP_IMAGE,swtpmsvc)" >> $@
	$Qecho "HCP_IMAGE_TOOLS=$(call HCP_IMAGE,tools)" >> $@
	$Qecho "HCP_IMAGE_CABOODLE=$(call HCP_IMAGE,caboodle)" >> $@
	$Qecho "HCP_TESTCREDS_ENROLLSIGNER=$(HCP_TESTCREDS_ENROLLSIGNER)" >> $@
	$Qecho "HCP_TESTCREDS_ENROLLVERIFIER=$(HCP_TESTCREDS_ENROLLVERIFIER)" >> $@
	$Qecho "HCP_TESTCREDS_ENROLLCERTISSUER=$(HCP_TESTCREDS_ENROLLCERTISSUER)" >> $@
	$Qecho "HCP_ORCHESTRATOR_JSON=$(HCP_ORCHESTRATOR_JSON)" >> $@
	$Qecho "" >> $@
	$Qecho "# Variables copied from (HCP_APPS_SRC)/usecase/common.env;" >> $@
	$Qcat $(HCP_APPS_SRC)/usecase/common.env | egrep -v "^#" | \
		sed -e "s/^export //" >> $@
ALL += $(HCP_OUT)/docker-compose.env

###################
# Cumulative rule #
###################

all: $(ALL)

########################
# Hierarchical cleanup #
########################

# This can be used as an order-only dependency (after a "|") for all "clean_*"
# rules that try to remove a container image. Why? Because even if we always
# pass "--rm" to docker-run, we can't entirely rid ourselves of
# exited-but-not-removed containers: if docker-build launches a container to
# run a Dockerfile command and it fails, _that_ container will linger, and in
# doing so it will prevent the removal of container images that are ancestors
# of it! Thus - this rule provides a way to detect that particular class of
# exited containers and remove them. Making sure it runs before your cleanup
# routine helps ensure your "docker image rm" statements don't fail.
preclean:
	$Qdocker container ls -a -q --filter=label=$(HCP_IMAGE_PREFIX)all | \
		xargs -r docker container rm

# As a discipline measure, we use 'rmdir' rather than 'rm -rf'. The concept is
# that the hierarchy of stuff that gets created inside $(HCP_OUT) should have
# corresponding clean targets and dependencies. Any child target should declare
# the parent to be dependent on it, to ensure that child rules run before
# parent rules.  This means that 'clean' should be dependent on the entire tree
# of cleanup targets for everything created underneath it, and so the rule for
# 'clean' should run after everything else. If everything is covered, nothing
# will be left and 'rmdir' will suffice. If we have to use 'rm -rf', it's
# because there are elements getting created that don't have a corresponding
# cleanup rule, or it's incomplete, or it hasn't created dependency hooks
# appropriately.
clean:
ifneq (,$(wildcard $(HCP_OUT)))
	$Qrm -f $(HCP_OUT)/docker-compose.env
	$Qrm -f $(HCP_OUT)/.deps.*
	$Qrmdir $(HCP_OUT)
endif

#######################
# Lazy-initialization #
#######################

# General-purpose directory creation. Adding any path to MDIRS ensures it gets
# this rule. That's why it's the the last declaration.  Note, we deliberately
# avoid "mkdir -p". It's a discipline measure, to ensure things don't get
# sloppy over time. If make tries to create a child directory before creating
# its parent, that's either because the child is in MDIRS but the parent isn't,
# or we're missing a "|" dependency (of the child upon the parent) to control
# the ordering.

$(MDIRS):
	$Qmkdir $@
