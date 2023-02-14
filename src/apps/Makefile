HCP_APPS_OUT := $(HCP_OUT)/apps
HCP_APPS_SRC := $(HCP_SRC)/apps

$(HCP_APPS_OUT): | $(HCP_OUT)
MDIRS += $(HCP_APPS_OUT)

#################
# APPS_PRE_BASE #
#################

# We create this layer with the commonly-required upstream packages _before_
# creating the APPS_BASE layer with the possibly-locally-built upstream and
# HCP-specific packages. This is because locally-built packages get (rightly)
# prioritized over upstream installs - to avoid accidental installation (by
# dependency) of upstream packages before locally-built equivalents get a
# chance - and so we don't want local source changes to cause the constant
# re-downloading and reinstallation of upstream packages. Ie. PRE_BASE forces
# those upstream packages to go in first, and so docker/buildkit caching takes
# care of the rest.
apps_pre_base_pkgs := json-glib-tools libjson-perl libncurses5-dev \
	python3 python3-yaml python3-netifaces python3-psutil \
	python3-cryptography python3-openssl \
	python3-flask python3-requests uwsgi-plugin-python3 \
	nginx uuid-runtime \
	openssh-server
$(eval $(call pp_add_layer,\
	APPS_PRE_BASE,\
	BASE,\
	APPS,\
	$(apps_pre_base_pkgs),\
	$(HCP_SRC)/apps/base.Dockerfile,\
	$(HCP_SRC)/apps/Makefile,\
	,\
	))

#############
# APPS_BASE #
#############

# HCP: generic code (env, launcher, webapi, attester, purger, ...)
apps_base_pkgs := hcp-common hcp-xtra hcp-tools
# HCP: app/service-specific code (enrollsvc, attestsvc, swtpmsvc, ...)
apps_base_pkgs += hcp-enrollsvc hcp-attestsvc hcp-policysvc hcp-swtpmsvc
# HCP: other apps/services (kdcsvc, sshsvc, ...)
apps_base_pkgs += hcp-kdcsvc hcp-sshsvc
# external packages, possibly locally-built
apps_base_pkgs += swtpm-tools libtpms0

$(eval $(call pp_add_layer,\
	APPS_BASE,\
	APPS_PRE_BASE,\
	APPS,\
	$(apps_base_pkgs),\
	,\
	$(HCP_SRC)/apps/Makefile,\
	,\
	))

# Include the app_image() subroutine
include $(HCP_APPS_SRC)/Makefile.sub

# hcp_common: base class for all HCP apps.
$(eval $(call app_image,common,SYM:APPS_BASE,safeboot tpmware heimdal,,))

# hcp_caboodle: at the other extreme, this contains everything. It's an image
# that can run any of the HCP apps/purposes, because it contains the code for
# all of it.
$(eval $(call app_image,caboodle,common,caboodle,,))

# Post-process now that all apps are registered
$(eval $(call app_image_post,common))
$(eval APPS_NAMES := $(strip $(APPS_NAMES)))
APPS := $(foreach i,$(APPS_NAMES),$(HCP_$i_TFILE))
ALL += $(APPS)

# Create a UMLified (bootable ext4 image) version of caboodle
$(eval $(call umlify,CABOODLE))

###########
# Wrapper #
###########

apps: $(APPS)

# Global cleanup
ifneq (,$(wildcard $(HCP_APPS_OUT)))
clean_apps:
	$Qrmdir $(HCP_APPS_OUT)
clean: clean_apps
endif
