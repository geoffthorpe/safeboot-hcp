# "base platform" layers
#
# An _ordered_ sequence of image layers that build a "base platform".
# Everything else is derived from the result of these layers.
#     0import
#         - imports the upstream/baseline image, see HCP_BASE in
#           hcp/settings.mk
#         - puts our (source) version into the image environment, see HCP_VER
#           in hcp/Makefile.
#     1apt-source
#         - optional, see HCP_1APT_ENABLE in hcp/settings.mk
#         - overrides or supplements the source repositories and signature keys
#           used for debian package installation.
#         - if enabled, the user should;
#           - add files (package source lists, signing keys, etc) to
#             $(HCP_BASE_SRC)/1apt-source-context,
#           - edit $(HCP_BASE_OUT)/1apt-source.Dockerfile accordingly to
#             inject those files, and
#           - uncomment HCP_1APT_FILES and list files in it so that changes to
#             them get picked up by dependency-handling.
#     2apt-usable
#         - twiddle with debconf and apt-utils to make the environment less
#           spartan and hostile.
#         - make the container image timezone-compatible with the host.
#     3platform
#         - installs a common, base-line set of system tools that should show up
#           in all other container images.
#     4add-cacerts
#         - optional, see SAFEBOOT_ADD_CACERTS in hcp/settings.mk
#         - install host-side trust roots (CA certificates).

HCP_BASE_SRC := $(HCP_SRC)/base
HCP_BASE_OUT := $(HCP_OUT)/base
HCP_BASE0_DNAME := $(call HCP_IMAGE,base_0import)
HCP_BASE1_DNAME := $(call HCP_IMAGE,base_1apt-source)
HCP_BASE1_TOUCHFILE := $(HCP_BASE_OUT)/1apt-source.built
HCP_BASE2_DNAME := $(call HCP_IMAGE,base_2apt-usable)
HCP_BASE2_TOUCHFILE := $(HCP_BASE_OUT)/2apt-usable.built
HCP_BASE3_DNAME := $(call HCP_IMAGE,base_3platform)
HCP_BASE3_TOUCHFILE := $(HCP_BASE_OUT)/3platform.built
HCP_BASE4_DNAME := $(call HCP_IMAGE,base_4add-cacerts)
HCP_BASE4_TOUCHFILE := $(HCP_BASE_OUT)/4add-cacerts.built

$(HCP_BASE_OUT): | $(HCP_OUT)
MDIRS += $(HCP_BASE_OUT)

# For downstream (builds, apps, ...) usage;
# - Depend on $(HCP_BASE_TOUCHFILE) to ensure it is (re)built as required.
# - Use "FROM $(HCP_BASE_DNAME)" to derive images.
ifdef HCP_4ADD_CACERTS_ENABLE
HCP_BASE_TOUCHFILE := $(HCP_BASE4_TOUCHFILE)
HCP_BASE_DNAME := $(HCP_BASE4_DNAME)
else
HCP_BASE_TOUCHFILE := $(HCP_BASE3_TOUCHFILE)
HCP_BASE_DNAME := $(HCP_BASE3_DNAME)
endif

# A wrapper target to build the "base platform" image
base: $(HCP_BASE_TOUCHFILE)
ALL += $(HCP_BASE_TOUCHFILE)

# A change to these files automatically puts (derived) Dockerfiles out of date.
HCP_BASE_DEPS_COMMON := $(HCP_DEPS_COMMON) $(HCP_BASE_SRC)/Makefile

# LAYER: 0import
#      - inherit the debian image we're based on (per hcp/settings.mk)
#      - stamps in the HCP_VER version

$(HCP_BASE_OUT)/0import.Dockerfile: | $(HCP_BASE_OUT)
$(HCP_BASE_OUT)/0import.Dockerfile: $(HCP_BASE_DEPS_COMMON)
$(HCP_BASE_OUT)/0import.Dockerfile:
	$Qecho "FROM $(HCP_BASE)" > $@
	$Qecho "ENV HCP_VER=$(HCP_VER)" >> $@
	$Qecho "LABEL $(HCP_IMAGE_PREFIX)all=1" >> $@

$(HCP_BASE_OUT)/0import.built: $(HCP_BASE_OUT)/0import.Dockerfile
$(HCP_BASE_OUT)/0import.built:
	$Qcat $(HCP_BASE_OUT)/0import.Dockerfile | \
		docker build -t $(HCP_BASE0_DNAME) -
	$Qtouch $@
$(eval $(call pp_rule_docker_image_rm,\
	$(HCP_BASE_OUT)/0import.built,\
	$(HCP_BASE0_DNAME),\
	base_0import,\
	clean_base))

# LAYER: 1apt-source

ifdef HCP_1APT_ENABLE

# HCP_1APT_FILES:= $(foreach i,<files...>,$(HCP_BASE_SRC)/1apt-source-context/$i)

$(HCP_BASE_OUT)/1apt-source.Dockerfile: | $(HCP_BASE_OUT)
$(HCP_BASE_OUT)/1apt-source.Dockerfile: $(HCP_BASE_DEPS_COMMON)
$(HCP_BASE_OUT)/1apt-source.Dockerfile: $(HCP_BASE_SRC)/1apt-source.Dockerfile
$(HCP_BASE_OUT)/1apt-source.Dockerfile: $(HCP_1APT_FILES)
$(HCP_BASE_OUT)/1apt-source.Dockerfile:
	$Qecho "FROM $(HCP_BASE0_DNAME)" > $@
	$Qcat $(HCP_BASE_SRC)/1apt-source.Dockerfile >> $@

$(HCP_BASE1_TOUCHFILE): $(HCP_BASE_OUT)/0import.built
$(HCP_BASE1_TOUCHFILE): $(HCP_BASE_OUT)/1apt-source.Dockerfile
$(HCP_BASE1_TOUCHFILE):
	$Qdocker build -t $(HCP_BASE1_DNAME) \
	               -f $(HCP_BASE_OUT)/1apt-source.Dockerfile \
	               $(HCP_BASE_SRC)/1apt-source-context/
	$Qtouch $@
$(eval $(call pp_rule_docker_image_rm,\
	$(HCP_BASE1_TOUCHFILE),\
	$(HCP_BASE1_DNAME),\
	base_1apt-source,\
	clean_base))

endif # HCP_1APT_ENABLE

# LAYER: 2apt-usable

HCP_BASE_2APT_SRC := $(HCP_BASE_SRC)/2apt-usable-context
HCP_BASE_2APT_OUT := $(HCP_BASE_OUT)/2apt-usable-context
$(HCP_BASE_2APT_OUT): | $(HCP_BASE_OUT)
MDIRS += $(HCP_BASE_2APT_OUT)

$(HCP_BASE_OUT)/2apt-usable.Dockerfile: | $(HCP_BASE_OUT)
$(HCP_BASE_OUT)/2apt-usable.Dockerfile: $(HCP_BASE_DEPS_COMMON)
$(HCP_BASE_OUT)/2apt-usable.Dockerfile: $(HCP_BASE_SRC)/2apt-usable.Dockerfile
$(HCP_BASE_OUT)/2apt-usable.Dockerfile:
ifdef HCP_1APT_ENABLE
	$Qecho "FROM $(HCP_BASE1_DNAME)" > $@
else
	$Qecho "FROM $(HCP_BASE0_DNAME)" > $@
endif
	$Qcat $(HCP_BASE_SRC)/2apt-usable.Dockerfile >> $@

$(HCP_BASE_2APT_OUT)/apt-proxy.sh: | $(HCP_BASE_2APT_OUT)
$(HCP_BASE_2APT_OUT)/apt-proxy.sh: $(HCP_BASE_2APT_SRC)/apt-proxy.sh
$(HCP_BASE_2APT_OUT)/apt-proxy.sh:
	$Qcp $< $@
$(HCP_BASE_2APT_OUT)/timezone: | $(HCP_BASE_2APT_OUT)
$(HCP_BASE_2APT_OUT)/timezone: /etc/timezone
$(HCP_BASE_2APT_OUT)/timezone:
	$Qcp $< $@

ifdef HCP_1APT_ENABLE
$(HCP_BASE2_TOUCHFILE): $(HCP_BASE1_TOUCHFILE)
else
$(HCP_BASE2_TOUCHFILE): $(HCP_BASE_OUT)/0import.built
endif
$(HCP_BASE2_TOUCHFILE): $(HCP_BASE_OUT)/2apt-usable.Dockerfile
$(HCP_BASE2_TOUCHFILE): $(HCP_BASE_2APT_OUT)/apt-proxy.sh
$(HCP_BASE2_TOUCHFILE): $(HCP_BASE_2APT_OUT)/timezone
$(HCP_BASE2_TOUCHFILE):
	$Qdocker build -t $(HCP_BASE2_DNAME) \
	               -f $(HCP_BASE_OUT)/2apt-usable.Dockerfile \
		       --build-arg HCP_APT_PROXY=$(HCP_APT_PROXY) \
	               $(HCP_BASE_2APT_OUT)/
	$Qtouch $@
$(eval $(call pp_rule_docker_image_rm,\
	$(HCP_BASE2_TOUCHFILE),\
	$(HCP_BASE2_DNAME),\
	base_2apt-usable,\
	clean_base))

# LAYER: 3platform

ifdef HCP_3PLATFORM_NO_TPM2
HCP_BASE_3PLATFORM_TPM2_TOOLS :=
else
HCP_BASE_3PLATFORM_TPM2_TOOLS := RUN apt-get install -y tpm2-tools
endif
ifdef HCP_3PLATFORM_XTRA
HCP_BASE_3PLATFORM_XTRA := RUN apt-get install -y $(HCP_3PLATFORM_XTRA)
else
HCP_BASE_3PLATFORM_XTRA :=
endif
$(HCP_BASE_OUT)/3platform.Dockerfile: | $(HCP_BASE_OUT)
$(HCP_BASE_OUT)/3platform.Dockerfile: $(HCP_BASE_DEPS_COMMON)
$(HCP_BASE_OUT)/3platform.Dockerfile: $(HCP_BASE_SRC)/3platform.Dockerfile
$(HCP_BASE_OUT)/3platform.Dockerfile:
	$Qecho "FROM $(HCP_BASE2_DNAME)" > $@
	$Qcat $(HCP_BASE_SRC)/3platform.Dockerfile | \
	sed -e "s/HCP_BASE_3PLATFORM_TPM2_TOOLS/$(HCP_BASE_3PLATFORM_TPM2_TOOLS)/" | \
	sed -e "s/HCP_BASE_3PLATFORM_XTRA/$(HCP_BASE_3PLATFORM_XTRA)/" >> $@

$(HCP_BASE3_TOUCHFILE): $(HCP_BASE2_TOUCHFILE)
$(HCP_BASE3_TOUCHFILE): $(HCP_BASE_OUT)/3platform.Dockerfile
$(HCP_BASE3_TOUCHFILE): $(HCP_BASE_SRC)/3platform-context/chowner.sh
$(HCP_BASE3_TOUCHFILE):
	$Qdocker build -t $(HCP_BASE3_DNAME) \
		-f $(HCP_BASE_OUT)/3platform.Dockerfile \
		$(HCP_BASE_SRC)/3platform-context/
	$Qtouch $@
$(eval $(call pp_rule_docker_image_rm,\
	$(HCP_BASE3_TOUCHFILE),\
	$(HCP_BASE3_DNAME),\
	base_3platform,\
	clean_base))

# LAYER: 4add-cacerts

ifdef HCP_4ADD_CACERTS_ENABLE

HCP_BASE_4CA_OUT := $(HCP_BASE_OUT)/4add-cacerts-context
$(HCP_BASE_4CA_OUT): | $(HCP_BASE_OUT)
MDIRS += $(HCP_BASE_4CA_OUT)

ifdef HCP_4ADD_CACERTS_PATH
define hcp_base_4ca_src
	$(eval b := $(shell basename $1))
$(HCP_BASE_4CA_OUT)/$b: | $(HCP_BASE_4CA_OUT)
$(HCP_BASE_4CA_OUT)/$b: $(HCP_4ADD_CACERTS_PATH)/$1
$(HCP_BASE_4CA_OUT)/$b:
	$Qcp $$< $$@
$(eval HCP_BASE_4CA_CERTS += $(HCP_BASE_4CA_OUT)/$b)
endef
HCP_BASE_4CA_CERT_SRC := $(shell cd $(HCP_4ADD_CACERTS_PATH) && find . -type f)
$(foreach i,$(HCP_BASE_4CA_CERT_SRC),$(eval $(call hcp_base_4ca_src,$i)))
endif

# The TESTCRED handling is completed in src/testcreds.Makefile
ifdef HCP_4ADD_CACERTS_TESTCRED
$(eval HCP_BASE_4CA_CERTS +=$(HCP_BASE_4CA_OUT)/HCP_TESTCRED.cert)
endif

$(HCP_BASE_OUT)/4add-cacerts.Dockerfile: | $(HCP_BASE_OUT)
$(HCP_BASE_OUT)/4add-cacerts.Dockerfile: $(HCP_BASE_DEPS_COMMON)
$(HCP_BASE_OUT)/4add-cacerts.Dockerfile: $(HCP_BASE_SRC)/4add-cacerts.Dockerfile
$(HCP_BASE_OUT)/4add-cacerts.Dockerfile:
	$Qecho "FROM $(HCP_BASE3_DNAME)" > $@
	$Qcat $(HCP_BASE_SRC)/4add-cacerts.Dockerfile >> $@

$(HCP_BASE4_TOUCHFILE): $(HCP_BASE3_TOUCHFILE)
$(HCP_BASE4_TOUCHFILE): $(HCP_BASE_OUT)/4add-cacerts.Dockerfile
$(HCP_BASE4_TOUCHFILE): $(HCP_BASE_4CA_CERTS)
$(HCP_BASE4_TOUCHFILE):
	$Qdocker build -t $(HCP_BASE4_DNAME) \
	               -f $(HCP_BASE_OUT)/4add-cacerts.Dockerfile \
	               $(HCP_BASE_4CA_OUT)/
	$Qtouch $@
$(eval $(call pp_rule_docker_image_rm,\
	$(HCP_BASE4_TOUCHFILE),\
	$(HCP_BASE4_DNAME),\
	base_4add-cacerts,\
	clean_base))

endif # HCP_4ADD_CACERTS_ENABLE

# Cleanup
ifneq (,$(wildcard $(HCP_BASE_OUT)))
clean_base: | preclean
	$Qrm -f $(HCP_BASE_OUT)/4add-cacerts.*
	$Qrm -rf $(HCP_BASE_4CA_OUT)
	$Qrm -f $(HCP_BASE_OUT)/3platform.Dockerfile
	$Qrm -f $(HCP_BASE_OUT)/2apt-usable.Dockerfile
	$Qrm -rf $(HCP_BASE_2APT_OUT)
	$Qrm -f $(HCP_BASE_OUT)/1apt-source.Dockerfile
	$Qrm -f $(HCP_BASE_OUT)/0import.Dockerfile
	$Qrmdir $(HCP_BASE_OUT)
# Cleanup ordering
clean: clean_base
endif
