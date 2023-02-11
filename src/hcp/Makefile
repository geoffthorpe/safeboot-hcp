hcp_PKG_SRC := $(HCP_SRC)/hcp

# HCP_VERSION is in settings.mk
# TODO: the DPKG_RELEASE part of the package version is not getting generated.
# Commented-out here and absent in the subsequent sections.
#hcp_DPKG_RELEASE ?= 1
hcp_DPKG_ARCH ?= all
hcp_DPKG_SUFFIX := _$(HCP_VERSION)_$(hcp_DPKG_ARCH).deb
#hcp_DPKG_SUFFIX := _$(HCP_VERSION)-$(hcp_DPKG_RELEASE)_$(hcp_DPKG_ARCH).deb

##############
# hcp-common #
##############

hcpcommon_PKGS := hcp-common
hcpcommon_CANONICAL := hcp-common
hcpcommon_PKG_SRC := $(hcp_PKG_SRC)/common
hcpcommon_PKG_REFFILE := ./hcp.sh
hcpcommon_PKG_CMD_BOOTSTRAP := true
hcpcommon_PKG_CMD_PACKAGE := debuild -uc -us
hcp-common_DEPENDS :=

############
# hcp-xtra #
############

hcpxtra_PKGS := hcp-xtra
hcpxtra_CANONICAL := hcp-xtra
hcpxtra_PKG_SRC := $(hcp_PKG_SRC)/xtra
hcpxtra_PKG_REFFILE := ./HcpHostname.py
hcpxtra_PKG_CMD_BOOTSTRAP := true
hcpxtra_PKG_CMD_PACKAGE := debuild -uc -us
hcp-xtra_DEPENDS := hcp-common

#############
# hcp-tools #
#############

hcptools_PKGS := hcp-tools
hcptools_CANONICAL := hcp-tools
hcptools_PKG_SRC := $(hcp_PKG_SRC)/tools
hcptools_PKG_REFFILE := ./run_client.sh
hcptools_PKG_CMD_BOOTSTRAP := true
hcptools_PKG_CMD_PACKAGE := debuild -uc -us
hcp-tools_DEPENDS := hcp-common hcp-xtra

#################
# hcp-enrollsvc #
#################

hcpenrollsvc_PKGS := hcp-enrollsvc
hcpenrollsvc_CANONICAL := hcp-enrollsvc
hcpenrollsvc_PKG_SRC := $(hcp_PKG_SRC)/enrollsvc
hcpenrollsvc_PKG_REFFILE := ./mgmt_api.py
hcpenrollsvc_PKG_CMD_BOOTSTRAP := true
hcpenrollsvc_PKG_CMD_PACKAGE := debuild -uc -us
hcp-enrollsvc_DEPENDS := hcp-common hcp-xtra

#################
# hcp-attestsvc #
#################

hcpattestsvc_PKGS := hcp-attestsvc
hcpattestsvc_CANONICAL := hcp-attestsvc
hcpattestsvc_PKG_SRC := $(hcp_PKG_SRC)/attestsvc
hcpattestsvc_PKG_REFFILE := ./hcp_api.py
hcpattestsvc_PKG_CMD_BOOTSTRAP := true
hcpattestsvc_PKG_CMD_PACKAGE := debuild -uc -us
hcp-attestsvc_DEPENDS := hcp-common hcp-xtra

#################
# hcp-policysvc #
#################

hcppolicysvc_PKGS := hcp-policysvc
hcppolicysvc_CANONICAL := hcp-policysvc
hcppolicysvc_PKG_SRC := $(hcp_PKG_SRC)/policysvc
hcppolicysvc_PKG_REFFILE := ./policy_api.py
hcppolicysvc_PKG_CMD_BOOTSTRAP := true
hcppolicysvc_PKG_CMD_PACKAGE := debuild -uc -us
hcp-policysvc_DEPENDS := hcp-common hcp-xtra

################
# hcp-swtpmsvc #
################

hcpswtpmsvc_PKGS := hcp-swtpmsvc
hcpswtpmsvc_CANONICAL := hcp-swtpmsvc
hcpswtpmsvc_PKG_SRC := $(hcp_PKG_SRC)/swtpmsvc
hcpswtpmsvc_PKG_REFFILE := ./run_swtpm.sh
hcpswtpmsvc_PKG_CMD_BOOTSTRAP := true
hcpswtpmsvc_PKG_CMD_PACKAGE := debuild -uc -us
# TODO: if tpm2-* was a choice between upstream and 'debbuilder', listing it
# here would not be a problem. But while we use 'builder', this is a problem.
#hcp-swtpmsvc_DEPENDS := hcp-common hcp-xtra tpm2-tools tpm2-tss swtpm libtpms0
hcp-swtpmsvc_DEPENDS := hcp-common hcp-xtra swtpm libtpms0

##############
# hcp-kdcsvc #
##############

hcpkdcsvc_PKGS := hcp-kdcsvc
hcpkdcsvc_CANONICAL := hcp-kdcsvc
hcpkdcsvc_PKG_SRC := $(hcp_PKG_SRC)/kdcsvc
hcpkdcsvc_PKG_REFFILE := ./mgmt_api.py
hcpkdcsvc_PKG_CMD_BOOTSTRAP := true
hcpkdcsvc_PKG_CMD_PACKAGE := debuild -uc -us
# TODO: same note
#hcp-kdcsvc_DEPENDS := hcp-common hcp-xtra hcp-tools tpm2-tools tpm2-tss
hcp-kdcsvc_DEPENDS := hcp-common hcp-xtra hcp-tools

##############
# hcp-sshsvc #
##############

hcpsshsvc_PKGS := hcp-sshsvc
hcpsshsvc_CANONICAL := hcp-sshsvc
hcpsshsvc_PKG_SRC := $(hcp_PKG_SRC)/sshsvc
hcpsshsvc_PKG_REFFILE := ./run_sshd.py
hcpsshsvc_PKG_CMD_BOOTSTRAP := true
hcpsshsvc_PKG_CMD_PACKAGE := debuild -uc -us
# TODO: same note
#hcp-sshsvc_DEPENDS := hcp-common hcp-xtra hcp-tools tpm2-tools tpm2-tss
hcp-sshsvc_DEPENDS := hcp-common hcp-xtra hcp-tools

###################
# Turn the crank! #
###################

list_lower := common xtra tools enrollsvc attestsvc policysvc swtpmsvc \
		kdcsvc sshsvc
# Prepare missing inputs for debian_build()
$(foreach s,$(list_lower),$(foreach p,$(hcp$s_PKGS),\
$(eval $p_LOCAL_FILE := $p$(hcp_DPKG_SUFFIX))))

# Generate the layers and package output symbols, dependencies, etc
$(eval $(call debian_build,\
	$(foreach s,$(list_lower),hcp$s),\
	DEBBUILDER,\
	$(hcp_PKG_SRC)/Makefile))

# Process the output of debian_build()
$(eval package_outputs :=)
$(foreach s,$(list_lower),$(foreach p,$(hcp$s_PKGS),\
$(eval package_outputs += $($p_LOCAL_PATH))))

hcp_pkgs: $(package_outputs)
