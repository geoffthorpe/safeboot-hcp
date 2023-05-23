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

# LAYER: 0import
#      - inherit the debian image we're based on (per hcp/settings.mk)

BASE0_IMG_PARENT := ORIGIN
BASE0_OUT_PARENT := BASE_LAYERS
BASE0_DEPFILES := $(HCP_DEPS_COMMON) $(HCP_BASE_LAYERS_SRC)/Makefile
$(eval $(call hcp_image_derive,BASE0))

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

BASE1_IMG_PARENT := BASE0
BASE1_OUT_PARENT := BASE_LAYERS
BASE1_FILES := $(shell cd $(HCP_BASE_LAYERS_SRC)/base1 && ls)
BASE1_DSTUB := $(HCP_BASE_LAYERS_SRC)/1apt-source.Dockerfile
$(eval $(call hcp_image_derive,BASE1))

ANCESTOR2 := BASE1

else

ANCESTOR2 := BASE0

endif # HCP_1APT_ENABLE

# LAYER: 2apt-usable
#      - twiddle with debconf and apt-utils to make the environment less
#        spartan and hostile.
#      - make the container image timezone-compatible with the host.

BASE2_IMG_PARENT := $(ANCESTOR2)
BASE2_OUT_PARENT := BASE_LAYERS
BASE2_FILES := /etc/timezone $(shell find $(HCP_BASE_LAYERS_SRC)/base2 -maxdepth 1 -type f)
BASE2_DSTUB := $(HCP_BASE_LAYERS_SRC)/2apt-usable.Dockerfile
$(eval $(call hcp_image_derive,BASE2))

# LAYER: 3platform
#      - installs a common, base-line set of system tools that should show up
#        in all other container images.

BASE3_IMG_PARENT := BASE2
BASE3_OUT_PARENT := BASE_LAYERS
BASE3_PKGS := $(HCP_3PLATFORM_XTRA)
BASE3_FILES := $(shell find $(HCP_BASE_LAYERS_SRC)/base3 -maxdepth 1 -type f)
BASE3_DSTUB := $(HCP_BASE_LAYERS_SRC)/3platform.Dockerfile
$(eval $(call hcp_image_derive,BASE3))

# LAYER: 4add-cacerts
#      - optional, see SAFEBOOT_ADD_CACERTS in hcp/settings.mk
#      - install host-side trust roots (CA certificates).

ifdef HCP_4ADD_CACERTS_PATH

FILES_4CA_CERT := $(shell find $(HCP_4ADD_CACERTS_PATH) -type f)
$(if $(strip $(FILES_4CA_CERT)),,\
	$(error HCP_4ADD_CACERTS_PATH ($(HCP_4ADD_CACERTS_PATH)) contains no CA certs))

BASE4_IMG_PARENT := BASE3
BASE4_OUT_PARENT := BASE_LAYERS
BASE4_FILES := $(FILES_4CA_CERT)
BASE4_DSTUB := $(HCP_BASE_LAYERS_SRC)/4add-cacerts.Dockerfile
$(eval $(call hcp_image_derive,BASE4))

ANCESTOR5 := BASE4

else

ANCESTOR5 := BASE3

endif # HCP_4ADD_CACERTS_PATH

# The "hcp_base" layer sits on top of all that we just did
BASE_IMG_PARENT := $(ANCESTOR5)
BASE_OUT_PARENT := BASE_LAYERS
$(eval $(call hcp_image_derive,BASE))

# A wrapper target to build the "base platform" image
base: $(HCP_BASE_TFILE)
