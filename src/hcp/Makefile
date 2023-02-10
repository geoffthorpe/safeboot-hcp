HCP_PKG_SRC := $(HCP_SRC)/hcp

# HCP_VERSION is in settings.mk
# TODO: the DPKG_RELEASE part of the package version is not getting generated.
# Commented-out here and absent in the subsequent sections.
#HCP_DPKG_RELEASE ?= 1
HCP_DPKG_ARCH ?= all
HCP_DPKG_SUFFIX := _$(HCP_VERSION)_$(HCP_DPKG_ARCH).deb
#HCP_DPKG_SUFFIX := _$(HCP_VERSION)-$(HCP_DPKG_RELEASE)_$(HCP_DPKG_ARCH).deb

##############
# hcp-common #
##############

hcpcommon_PKGS := hcp-common
hcpcommon_CANONICAL := hcp-common
HCPCOMMON_PKG_SRC := $(HCP_PKG_SRC)/common
HCPCOMMON_PKG_REFFILE := ./hcp.sh
HCPCOMMON_PKG_CMD_BOOTSTRAP := true
HCPCOMMON_PKG_CMD_PACKAGE := debuild -uc -us
hcp-common_DEPENDS :=

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

###################
# Turn the crank! #
###################

list_lower := common xtra tools enrollsvc attestsvc policysvc swtpmsvc \
		kdcsvc sshsvc
list_upper := COMMON XTRA TOOLS ENROLLSVC ATTESTSVC POLICYSVC SWTPMSVC \
		KDCSVC SSHSVC
# Prepare missing inputs for debian_build()
$(foreach s,$(list_lower),$(foreach p,$(hcp$s_PKGS),\
$(eval $p_LOCAL_FILE := $p$(HCP_DPKG_SUFFIX))))

# Generate the layers and package output symbols, dependencies, etc
$(eval $(call debian_build,\
	$(foreach s,$(list_upper),HCP$s),\
	DEBBUILDER,\
	$(HCP_PKG_SRC)/Makefile))

# Process the output of debian_build()
$(eval package_outputs :=)
$(foreach s,$(list_lower),$(foreach p,$(hcp$s_PKGS),\
$(eval package_outputs += $($p_LOCAL_PATH))))

hcp_pkgs: $(package_outputs)
