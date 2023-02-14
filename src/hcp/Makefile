hcp_PKG_SRC := $(HCP_SRC)/hcp

# TODO: these should all be packages in the same set, rather than distinct
# sets. Ie. a single src/hcp/debian directory that builds all the packages,
# rather than src/hcp/<pkg>/debian for each <pkg>. Issues:
# - by default, that debian build flow will expect to use _this_ Makefile to
#   "build HCP", but we can't take such liberties here, because this Makefile
#   is sourced by the top-level Makefile along with everything else in the HCP
#   tree.
# Solution: probably rename this file and change the site where it's included,
#   and create a new Makefile to handle the debian install details.)
# - how to write a Makefile and corresponding debian/control that will cause
#   "debuild" to build all the things? What targets to write? etc.

# HCP_VERSION is in settings.mk
# TODO: the PKG_RELEASE part of the package version is not getting generated.
# Commented-out here and absent in the subsequent sections.
#hcp_PKG_RELEASE ?= 1
hcp_PKG_ARCH ?= all
hcp_PKG_SUFFIX := _$(HCP_VERSION)_$(hcp_PKG_ARCH).deb
#hcp_PKG_SUFFIX := _$(HCP_VERSION)-$(hcp_PKG_RELEASE)_$(hcp_PKG_ARCH).deb

hcp_list := common xtra tools \
	enrollsvc attestsvc policysvc swtpmsvc \
	kdcsvc sshsvc

$(eval package_outputs :=)

$(foreach s,$(hcp_list),\
$(eval hcp-$s_PKG_SRC := $(hcp_PKG_SRC)/$s)\
$(eval hcp-$s_PKG_SUFFIX := $(hcp_PKG_SUFFIX))\
$(eval $(call debian_build,hcp-$s,DEBBUILDER,$(hcp_PKG_SRC)/Makefile))\
$(foreach p,$(hcp-$s_PKGS),$(eval package_outputs += $($p_LOCAL_PATH))))

hcp_pkgs: $(package_outputs)
