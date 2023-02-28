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
	openssh-server gnutls-bin libglib2.0-0 openssl
ifdef HCP_APP_UML
apps_pre_base_pkgs += vde2 kmod isc-dhcp-client
endif
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

# NB: the packages "gnutls-bin libglib2.0-0 openssl" were added to
# apps_pre_base because experience shows that they're needed by the tools
# below. Doing this minimizes/eliminates package downloads during a rebuild if
# in-tree soure is modified. That assumption might grow stale, which you'll
# notice if a change to any of the 'apps_base_pkgs' codebases causes download
# of upstream packages.
apps_base_pkgs := swtpm-tools tpm2-tools heimdal safeboot

$(eval $(call pp_add_layer,\
	APPS_BASE,\
	APPS_PRE_BASE,\
	APPS,\
	$(apps_base_pkgs),\
	,\
	$(HCP_SRC)/apps/Makefile,\
	,\
	))

############
# Caboodle #
############

$(eval $(call pp_add_layer,\
	CABOODLE,\
	APPS_BASE,\
	APPS,\
	hcp,\
	,\
	$(HCP_SRC)/apps/Makefile,\
	,\
	))

ifdef HCP_APP_UML
# Create a UMLified (bootable ext4 image) version of caboodle
$(eval $(call umlify,CABOODLE))
endif
