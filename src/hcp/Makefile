HCP_PKG_SRC := $(HCP_SRC)/hcp
HCP_PKG_OUT := $(HCP_OUT)/hcp
$(HCP_PKG_OUT): | $(HCP_OUT)
MDIRS += $(HCP_PKG_OUT)
ifneq (,$(wildcard $(HCP_PKG_OUT)))
clean_pkg:
	$Qrmdir $(HCP_PKG_OUT)
clean: clean_pkg
endif

##############
# hcp-common #
##############

# - expected packages, and the canonical choice
hcpcommon_PKGS := hcp-common
hcpcommon_CANONICAL := hcp-common
# - codebase info, how to build, etc
HCPCOMMON_PKG_SRC := $(HCP_PKG_SRC)/common
HCPCOMMON_PKG_REFFILE := ./hcp.sh
HCPCOMMON_PKG_CMD_BOOTSTRAP := true
HCPCOMMON_PKG_CMD_PACKAGE := debuild -uc -us
# - dependencies on any possibly-locally-built packages.
hcp-common_DEPENDS :=
# - expected package filenames, per debian conventions
HCPCOMMON_VERSION ?= 0.5
# TODO: the _RELEASE part of the package version is not getting generated.
# Commented-out here and absent in the subsequent sections.
#HCPCOMMON_RELEASE ?= 1
HCPCOMMON_ARCH ?= all
$(foreach p,$(hcpcommon_PKGS),\
	$(eval $p_LOCAL_FILE := \
		$p_$(HCPCOMMON_VERSION)_$(HCPCOMMON_ARCH).deb))
#		$p_$(HCPCOMMON_VERSION)-$(HCPCOMMON_RELEASE)_$(HCPCOMMON_ARCH).deb))

# Turn the crank
$(eval $(call debian_build,\
	HCPCOMMON,\
	DEBBUILDER,\
	$(HCP_PKG_SRC)/Makefile))

############
# hcp-xtra #
############

hcpxtra_PKGS := hcp-xtra
hcpxtra_CANONICAL := hcp-xtra

HCPXTRA_PKG_SRC := $(HCP_PKG_SRC)/xtra
HCPXTRA_PKG_REFFILE := ./HcpHostname.py
HCPXTRA_PKG_CMD_BOOTSTRAP := true
HCPXTRA_PKG_CMD_PACKAGE := debuild -uc -us

hcp-xtra_DEPENDS := hcp-common

HCPXTRA_VERSION ?= 0.5
HCPXTRA_ARCH ?= all
$(foreach p,$(hcpxtra_PKGS),\
	$(eval $p_LOCAL_FILE := \
		$p_$(HCPXTRA_VERSION)_$(HCPXTRA_ARCH).deb))

$(eval $(call debian_build,\
	HCPXTRA,\
	DEBBUILDER,\
	$(HCP_PKG_SRC)/Makefile))

#############
# hcp-tools #
#############

hcptools_PKGS := hcp-tools
hcptools_CANONICAL := hcp-tools

HCPTOOLS_PKG_SRC := $(HCP_PKG_SRC)/tools
HCPTOOLS_PKG_REFFILE := ./run_client.sh
HCPTOOLS_PKG_CMD_BOOTSTRAP := true
HCPTOOLS_PKG_CMD_PACKAGE := debuild -uc -us

hcp-tools_DEPENDS := hcp-common hcp-xtra

HCPTOOLS_VERSION ?= 0.5
HCPTOOLS_ARCH ?= all
$(foreach p,$(hcptools_PKGS),\
	$(eval $p_LOCAL_FILE := \
		$p_$(HCPTOOLS_VERSION)_$(HCPTOOLS_ARCH).deb))

$(eval $(call debian_build,\
	HCPTOOLS,\
	DEBBUILDER,\
	$(HCP_PKG_SRC)/Makefile))

#################
# hcp-enrollsvc #
#################

hcpenrollsvc_PKGS := hcp-enrollsvc
hcpenrollsvc_CANONICAL := hcp-enrollsvc

HCPENROLLSVC_PKG_SRC := $(HCP_PKG_SRC)/enrollsvc
HCPENROLLSVC_PKG_REFFILE := ./mgmt_api.py
HCPENROLLSVC_PKG_CMD_BOOTSTRAP := true
HCPENROLLSVC_PKG_CMD_PACKAGE := debuild -uc -us

hcp-enrollsvc_DEPENDS := hcp-common hcp-xtra

HCPENROLLSVC_VERSION ?= 0.5
HCPENROLLSVC_ARCH ?= all
$(foreach p,$(hcpenrollsvc_PKGS),\
	$(eval $p_LOCAL_FILE := \
		$p_$(HCPENROLLSVC_VERSION)_$(HCPENROLLSVC_ARCH).deb))

$(eval $(call debian_build,\
	HCPENROLLSVC,\
	DEBBUILDER,\
	$(HCP_PKG_SRC)/Makefile))

#################
# hcp-attestsvc #
#################

hcpattestsvc_PKGS := hcp-attestsvc
hcpattestsvc_CANONICAL := hcp-attestsvc

HCPATTESTSVC_PKG_SRC := $(HCP_PKG_SRC)/attestsvc
HCPATTESTSVC_PKG_REFFILE := ./hcp_api.py
HCPATTESTSVC_PKG_CMD_BOOTSTRAP := true
HCPATTESTSVC_PKG_CMD_PACKAGE := debuild -uc -us

hcp-attestsvc_DEPENDS := hcp-common hcp-xtra

HCPATTESTSVC_VERSION ?= 0.5
HCPATTESTSVC_ARCH ?= all
$(foreach p,$(hcpattestsvc_PKGS),\
	$(eval $p_LOCAL_FILE := \
		$p_$(HCPATTESTSVC_VERSION)_$(HCPATTESTSVC_ARCH).deb))

$(eval $(call debian_build,\
	HCPATTESTSVC,\
	DEBBUILDER,\
	$(HCP_PKG_SRC)/Makefile))

#################
# hcp-policysvc #
#################

hcppolicysvc_PKGS := hcp-policysvc
hcppolicysvc_CANONICAL := hcp-policysvc

HCPPOLICYSVC_PKG_SRC := $(HCP_PKG_SRC)/policysvc
HCPPOLICYSVC_PKG_REFFILE := ./policy_api.py
HCPPOLICYSVC_PKG_CMD_BOOTSTRAP := true
HCPPOLICYSVC_PKG_CMD_PACKAGE := debuild -uc -us

hcp-policysvc_DEPENDS := hcp-common hcp-xtra

HCPPOLICYSVC_VERSION ?= 0.5
HCPPOLICYSVC_ARCH ?= all
$(foreach p,$(hcppolicysvc_PKGS),\
	$(eval $p_LOCAL_FILE := \
		$p_$(HCPPOLICYSVC_VERSION)_$(HCPPOLICYSVC_ARCH).deb))

$(eval $(call debian_build,\
	HCPPOLICYSVC,\
	DEBBUILDER,\
	$(HCP_PKG_SRC)/Makefile))

################
# hcp-swtpmsvc #
################

hcpswtpmsvc_PKGS := hcp-swtpmsvc
hcpswtpmsvc_CANONICAL := hcp-swtpmsvc

HCPSWTPMSVC_PKG_SRC := $(HCP_PKG_SRC)/swtpmsvc
HCPSWTPMSVC_PKG_REFFILE := ./run_swtpm.sh
HCPSWTPMSVC_PKG_CMD_BOOTSTRAP := true
HCPSWTPMSVC_PKG_CMD_PACKAGE := debuild -uc -us

# TODO: if tpm2-* was a choice between upstream and 'debbuilder', listing it
# here would not be a problem. But while we use 'builder', this is a problem.
#hcp-swtpmsvc_DEPENDS := hcp-common hcp-xtra tpm2-tools tpm2-tss swtpm libtpms0
hcp-swtpmsvc_DEPENDS := hcp-common hcp-xtra swtpm libtpms0

HCPSWTPMSVC_VERSION ?= 0.5
HCPSWTPMSVC_ARCH ?= all
$(foreach p,$(hcpswtpmsvc_PKGS),\
	$(eval $p_LOCAL_FILE := \
		$p_$(HCPSWTPMSVC_VERSION)_$(HCPSWTPMSVC_ARCH).deb))

$(eval $(call debian_build,\
	HCPSWTPMSVC,\
	DEBBUILDER,\
	$(HCP_PKG_SRC)/Makefile))

##############
# hcp-kdcsvc #
##############

hcpkdcsvc_PKGS := hcp-kdcsvc
hcpkdcsvc_CANONICAL := hcp-kdcsvc

HCPKDCSVC_PKG_SRC := $(HCP_PKG_SRC)/kdcsvc
HCPKDCSVC_PKG_REFFILE := ./mgmt_api.py
HCPKDCSVC_PKG_CMD_BOOTSTRAP := true
HCPKDCSVC_PKG_CMD_PACKAGE := debuild -uc -us

# TODO: same note
#hcp-kdcsvc_DEPENDS := hcp-common hcp-xtra hcp-tools tpm2-tools tpm2-tss
hcp-kdcsvc_DEPENDS := hcp-common hcp-xtra hcp-tools

HCPKDCSVC_VERSION ?= 0.5
HCPKDCSVC_ARCH ?= all
$(foreach p,$(hcpkdcsvc_PKGS),\
	$(eval $p_LOCAL_FILE := \
		$p_$(HCPKDCSVC_VERSION)_$(HCPKDCSVC_ARCH).deb))

$(eval $(call debian_build,\
	HCPKDCSVC,\
	DEBBUILDER,\
	$(HCP_PKG_SRC)/Makefile))

##############
# hcp-sshsvc #
##############

hcpsshsvc_PKGS := hcp-sshsvc
hcpsshsvc_CANONICAL := hcp-sshsvc

HCPSSHSVC_PKG_SRC := $(HCP_PKG_SRC)/sshsvc
HCPSSHSVC_PKG_REFFILE := ./run_sshd.py
HCPSSHSVC_PKG_CMD_BOOTSTRAP := true
HCPSSHSVC_PKG_CMD_PACKAGE := debuild -uc -us

# TODO: same note
#hcp-sshsvc_DEPENDS := hcp-common hcp-xtra hcp-tools tpm2-tools tpm2-tss
hcp-sshsvc_DEPENDS := hcp-common hcp-xtra hcp-tools

HCPSSHSVC_VERSION ?= 0.5
HCPSSHSVC_ARCH ?= all
$(foreach p,$(hcpsshsvc_PKGS),\
	$(eval $p_LOCAL_FILE := \
		$p_$(HCPSSHSVC_VERSION)_$(HCPSSHSVC_ARCH).deb))

$(eval $(call debian_build,\
	HCPSSHSVC,\
	DEBBUILDER,\
	$(HCP_PKG_SRC)/Makefile))
