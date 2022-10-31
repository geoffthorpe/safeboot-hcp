#######################################
# Top-level control, defaults, config #
#######################################

TOP := $(shell pwd)
Q := $(if $(strip $V),,@)
export DOCKER_BUILDKIT := 1
export BUILDKIT_PROGRESS := plain

default: all

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

######################################
# Environment for docker-compose.yml #
######################################

# Regenerate the docker-compose.env if anything relevant changes. Depends on;
# - the output directory existing (HCP_OUT)
# - settings not being newer
# - this Makefile not being newer
# - the testcreds Makefile not being newer
# - no new activity in the apps output (this is where, for example, we learn
#   about the split between APP_IMAGES/APP_ALIASES)
$(HCP_OUT)/docker-compose.env: | $(HCP_OUT)
$(HCP_OUT)/docker-compose.env: $(TOP)/settings.mk
$(HCP_OUT)/docker-compose.env: $(TOP)/Makefile
$(HCP_OUT)/docker-compose.env: $(HCP_SRC)/testcreds.Makefile
$(HCP_OUT)/docker-compose.env: $(HCP_APPS_OUT)
$(foreach i,$(APP_IMAGES),\
$(eval IMAGE_LIST_CMD += echo "HCP_IMAGE_$i=$(call HCP_IMAGE,$i)" >> $(HCP_OUT)/docker-compose.env;))
$(foreach i,$(APP_ALIASES),\
$(eval IMAGE_LIST_CMD += echo "HCP_IMAGE_$i=$(call HCP_IMAGE,$(APP_ALIAS_$i))" >> $(HCP_OUT)/docker-compose.env;))
$(HCP_OUT)/docker-compose.env:
	$Qecho "Generating: docker-compose.env"
	$Qecho "## Autogenerated environment, used by docker-compose.yml" > $@
	$Qecho "" >> $@
	$Qecho "# Variables produced by the build environment;" >> $@
	$Q$(IMAGE_LIST_CMD)
	$Qecho "HCP_TESTCREDS_ENROLLCERTISSUER=$(HCP_TESTCREDS_ENROLLCERTISSUER)" >> $@
	$Qecho "HCP_TESTCREDS_ENROLLCERTCHECKER=$(HCP_TESTCREDS_ENROLLCERTCHECKER)" >> $@
	$Qecho "HCP_TESTCREDS_ENROLLSIGNER=$(HCP_TESTCREDS_ENROLLSIGNER)" >> $@
	$Qecho "HCP_TESTCREDS_ENROLLVERIFIER=$(HCP_TESTCREDS_ENROLLVERIFIER)" >> $@
	$Qecho "HCP_TESTCREDS_ENROLLCLIENT=$(HCP_TESTCREDS_ENROLLCLIENT)" >> $@
	$Qecho "HCP_TESTCREDS_ENROLLSERVER=$(HCP_TESTCREDS_ENROLLSERVER)" >> $@
	$Qecho "HCP_TOP=$(TOP)" >> $@
ALL += $(HCP_OUT)/docker-compose.env

#########
# Tests #
#########

include tests/Makefile

###################
# Cumulative rule #
###################

$(HCP_OUT)/.deps.done: $(DEPS)
	$Qtouch $@
	$Qecho "Completed 'deps' target"
deps: $(HCP_OUT)/.deps.done
$(HCP_OUT)/.all.done: $(ALL)
	$Qtouch $@
	$Qecho "Completed 'all' target"
all: $(HCP_OUT)/.all.done

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
	$Qrm -f $(HCP_OUT)/.all.done
	$Qrmdir $(HCP_OUT)
clean: clean_deps
endif
clean_deps:
ifneq (,$(wildcard $(HCP_OUT)))
	$Qrm -f $(HCP_OUT)/.deps.*
endif

#######################
# Lazy-initialization #
#######################

# General-purpose directory creation. Adding any path to MDIRS ensures it gets
# this rule. That's why it's the last declaration.  Note, we deliberately avoid
# "mkdir -p". It's a discipline measure, to ensure things don't get sloppy over
# time. If make tries to create a child directory before creating its parent,
# that's either because the child is in MDIRS but the parent isn't, or we're
# missing a "|" dependency (of the child upon the parent) to control the
# ordering.

$(MDIRS):
	$Qmkdir $@
