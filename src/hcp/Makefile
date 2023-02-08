HCP_PKG_SRC := $(HCP_SRC)/hcp
HCP_PKG_OUT := $(HCP_OUT)/hcp
$(HCP_PKG_OUT): | $(HCP_OUT)
MDIRS += $(HCP_PKG_OUT)
ifneq (,$(wildcard $(HCP_PKG_OUT)))
clean_pkg:
	$Qrmdir $(HCP_PKG_OUT)
clean: clean_pkg
endif

# Layer to build hcp-*
$(eval $(call pp_add_layer,\
	DBB_HCPAPP,\
	DEBBUILDER,\
	PKG,\
	,\
	,\
	$(HCP_PKG_SRC)/Makefile,\
	$(HCP_PKG_SRC)/common))

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
#HCPCOMMON_RELEASE ?= 1 # <-- the packages are missing this
HCPCOMMON_ARCH ?= all
$(foreach p,$(hcpcommon_PKGS),\
	$(eval $p_LOCAL_FILE := \
		$p_$(HCPCOMMON_VERSION)_$(HCPCOMMON_ARCH).deb))
#		$p_$(HCPCOMMON_VERSION)-$(HCPCOMMON_RELEASE)_$(HCPCOMMON_ARCH).deb))

# Turn the crank
$(eval $(call pp_add_dpkg_build,\
	HCPCOMMON,\
	DBB_HCPAPP))

############
# hcp-xtra #
############

# - expected packages, and the canonical choice
hcpxtra_PKGS := hcp-xtra
hcpxtra_CANONICAL := hcp-xtra
# - codebase info, how to build, etc
HCPXTRA_PKG_SRC := $(HCP_PKG_SRC)/xtra
HCPXTRA_PKG_REFFILE := ./HcpHostname.py
HCPXTRA_PKG_CMD_BOOTSTRAP := true
HCPXTRA_PKG_CMD_PACKAGE := debuild -uc -us
# - dependencies on any possibly-locally-built packages.
hcp-xtra_DEPENDS := hcp-common
# - expected package filenames, per debian conventions
HCPXTRA_VERSION ?= 0.5
HCPXTRA_ARCH ?= all
$(foreach p,$(hcpxtra_PKGS),\
	$(eval $p_LOCAL_FILE := \
		$p_$(HCPXTRA_VERSION)_$(HCPXTRA_ARCH).deb))

# Turn the crank
$(eval $(call pp_add_dpkg_build,\
	HCPXTRA,\
	DBB_HCPAPP))
