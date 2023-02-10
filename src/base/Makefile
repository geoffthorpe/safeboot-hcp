# "base platform" layers
#
# An _ordered_ sequence of image layers that build a "base platform".
# Everything else is derived from the result of these layers.

HCP_BASE_LAYERS_SRC := $(HCP_SRC)/base
HCP_BASE_LAYERS_OUT := $(HCP_OUT)/base
$(HCP_BASE_LAYERS_OUT): | $(HCP_OUT)
MDIRS += $(HCP_BASE_LAYERS_OUT)
ifneq (,$(wildcard $(HCP_BASE_LAYERS_OUT)))
clean_base_layers:
	$Qrmdir $(HCP_BASE_LAYERS_OUT)
clean: clean_base_layers
endif

# settings.mk defines HCP_ORIGIN_DNAME. To pass "ORIGIN" as the "ancestor" to
# pp_add_layer(), we must define a HCP_ORIGIN_TFILE and a corresponding rule.
HCP_ORIGIN_TFILE := $(HCP_BASE_LAYERS_OUT)/origin.imported
$(HCP_ORIGIN_TFILE): | $(HCP_BASE_LAYERS_OUT)
$(HCP_ORIGIN_TFILE):
	$Qdocker pull $(HCP_ORIGIN_DNAME)
	$Qtouch $@
ifneq (,$(wildcard $(HCP_ORIGIN_TFILE)))
clean_base_origin:
	$Qrm $(HCP_ORIGIN_TFILE)
clean_base_layers: clean_base_origin
endif

# A change to these files automatically puts (derived) Dockerfiles out of date.
HCP_BASE_LAYERS_DEPS_COMMON := $(HCP_DEPS_COMMON) \
				$(HCP_BASE_LAYERS_SRC)/Makefile

# LAYER: 0import
#      - inherit the debian image we're based on (per hcp/settings.mk)

$(eval $(call pp_add_layer,\
	BASE0,\
	ORIGIN,\
	BASE_LAYERS,\
	,\
	,\
	$(HCP_BASE_LAYERS_DEPS_COMMON),\
	,\
	))

# LAYER: 1apt-source
#      - optional, see HCP_1APT_ENABLE in hcp/settings.mk
#      - overrides or supplements the source repositories and signature keys
#        used for debian package installation.
#      - if enabled, the user should;
#        - add files (package source lists, signing keys, etc) to
#          $(HCP_BASE_LAYERS_SRC)/1apt-source-context,
#        - edit $(HCP_BASE_LAYERS_OUT)/1apt-source.Dockerfile accordingly to
#          inject those files, and
#        - uncomment HCP_1APT_FILES and list files in it so that changes to
#          them get picked up by dependency-handling.

ifdef HCP_1APT_ENABLE

FILES_1APT:= $(shell cd $(HCP_BASE_LAYERS_SRC)/base1 && ls)

$(eval $(call pp_add_layer,\
	BASE1,\
	BASE0,\
	BASE_LAYERS,\
	,\
	$(HCP_BASE_LAYERS_SRC)/1apt-source.Dockerfile,\
	,\
	$(FILES_1APT),\
	))

ANCESTOR2 := BASE1

else

ANCESTOR2 := BASE0

endif # HCP_1APT_ENABLE

# LAYER: 2apt-usable
#      - twiddle with debconf and apt-utils to make the environment less
#        spartan and hostile.
#      - make the container image timezone-compatible with the host.

FILES_2APT := $(shell cd $(HCP_BASE_LAYERS_SRC)/base2 && ls)

$(eval $(call pp_add_layer,\
	BASE2,\
	$(ANCESTOR2),\
	BASE_LAYERS,\
	,\
	$(HCP_BASE_LAYERS_SRC)/2apt-usable.Dockerfile,\
	,\
	$(FILES_2APT),\
	/etc/timezone))

# LAYER: 3platform
#      - installs a common, base-line set of system tools that should show up
#        in all other container images.

FILES_3PLATFORM := $(shell cd $(HCP_BASE_LAYERS_SRC)/base3 && ls)

$(eval $(call pp_add_layer,\
	BASE3,\
	BASE2,\
	BASE_LAYERS,\
	$(HCP_3PLATFORM_XTRA),\
	$(HCP_BASE_LAYERS_SRC)/3platform.Dockerfile,\
	,\
	$(FILES_3PLATFORM),\
	))

# LAYER: 4add-cacerts
#      - optional, see SAFEBOOT_ADD_CACERTS in hcp/settings.mk
#      - install host-side trust roots (CA certificates).

ifdef HCP_4ADD_CACERTS_PATH

FILES_4CA_CERT := $(shell find $(HCP_4ADD_CACERTS_PATH) -type f)
$(if $(strip $(FILES_4CA_CERT)),,\
	$(error HCP_4ADD_CACERTS_PATH ($(HCP_4ADD_CACERTS_PATH)) contains no CA certs))

$(eval $(call pp_add_layer,\
	BASE4,\
	BASE3,\
	BASE_LAYERS,\
	,\
	$(HCP_BASE_LAYERS_SRC)/4add-cacerts.Dockerfile,\
	,\
	,\
	$(FILES_4CA_CERT)))

ANCESTOR5 := BASE4

else

ANCESTOR5 := BASE3

endif # HCP_4ADD_CACERTS_PATH

# The "hcp_base" layer sits on top of all that we just did
$(eval $(call pp_add_layer,\
	BASE,\
	$(ANCESTOR5),\
	BASE_LAYERS,\
	,\
	,\
	,\
	,\
	))

# A wrapper target to build the "base platform" image
base: $(HCP_BASE_TFILE)
ALL += $(HCP_BASE_TFILE)
