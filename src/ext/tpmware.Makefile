HCP_TPMWARE_SRC := $(TOP)/ext-tpmware
HCP_TPMWARE_PREFIX := /usr

# Only compile-in tpm2-tss and tpm2-tools if we're not using upstream packages
ifdef HCP_LOCAL_TPM2

############
# tpm2-tss #
############

tpm2-tss_CMD_BOOTSTRAP := ./bootstrap
tpm2-tss_CMD_CONFIGURE := ./configure --disable-doxygen-doc --prefix=$(HCP_TPMWARE_PREFIX)
tpm2-tss_CMD_COMPILE := make $(HCP_BUILDER_MAKE_PARALLEL)
tpm2-tss_CMD_INSTALL := make $(HCP_BUILDER_MAKE_PARALLEL) install
$(eval $(call builder_add,\
	tpm2-tss,\
	$(HCP_TPMWARE_SRC)/tpm2-tss,\
	,\
	,\
	))
$(eval $(call builder_simpledep,tpm2-tss))

##############
# tpm2-tools #
##############

# Bug alert: previously, setting PKG_CONFIG_PATH was enough for tpm2-tools to
# detect everything it needs. Now, it fails to find "tss2-esys>=2.4.0" and
# suggests setting TSS2_ESYS_2_3_{CFLAGS,LIBS} "to avoid the need to call
# pkg-config". Indeed, setting these works, but those same settings should have
# been picked up from the pkgconfig directory...
HACK_TPM2-TOOLS += PKG_CONFIG_PATH=$(HCP_TPMWARE_PREFIX)/lib/pkgconfig
HACK_TPM2-TOOLS += TSS2_ESYS_2_3_CFLAGS=\"-I$(HCP_TPMWARE_PREFIX)/include -I$(HCP_TPMWARE_PREFIX)/include/tss2\"
HACK_TPM2-TOOLS += TSS2_ESYS_2_3_LIBS=\"-L$(HCP_TPMWARE_PREFIX)/lib -ltss2-esys\"
tpm2-tools_CMD_BOOTSTRAP := $(HACK_TPM2-TOOLS) ./bootstrap
tpm2-tools_CMD_CONFIGURE := $(HACK_TPM2-TOOLS) ./configure --prefix=$(HCP_TPMWARE_PREFIX)
tpm2-tools_CMD_COMPILE := $(HACK_TPM2-TOOLS) make $(HCP_BUILDER_MAKE_PARALLEL)
tpm2-tools_CMD_INSTALL := $(HACK_TPM2-TOOLS) make $(HCP_BUILDER_MAKE_PARALLEL) install
$(eval $(call builder_add,\
	tpm2-tools,\
	$(HCP_TPMWARE_SRC)/tpm2-tools,\
	tpm2-tss,\
	tpm2-tss,\
	))
$(eval $(call builder_simpledep,tpm2-tools))

endif # HCP_LOCAL_TPM2
