HCP_TPMWARE_SRC := $(TOP)/ext-tpmware
HCP_TPMWARE_INSTALL_DEST := /install-tpmware

HCP_TPMWARE_MAKE_PARALLEL ?= $(HCP_BUILDER_MAKE_PARALLEL)

# "tpmware" is the package of codebases, "install" is the tarball it creates
$(eval $(call builder_initialize,\
	tpmware,\
	$(HCP_TPMWARE_SRC),\
	$(HCP_TPMWARE_INSTALL_DEST),\
	$(HCP_TPMWARE_SUBMODULE_RESET),\
	$(HCP_TPMWARE_SUBMODULE_TARGETS)))

# Only compile-in tpm2-tss and tpm2-tools if we're not using upstream packages
ifdef HCP_LOCAL_TPM2

############
# tpm2-tss #
############

$(eval $(call builder_add_codebase,\
	tpmware,\
	tpm2-tss,\
	,\
	tpm2-tss,\
	bootstrap,\
	./bootstrap,\
	./configure --disable-doxygen-doc --prefix=$(HCP_TPMWARE_INSTALL_DEST),\
	make $(HCP_TPMWARE_MAKE_PARALLEL),\
	make $(HCP_TPMWARE_MAKE_PARALLEL) install))
$(eval $(call builder_codebase_simpledep,\
	tpmware,\
	tpm2-tss))

##############
# tpm2-tools #
##############

# Bug alert: previously, setting PKG_CONFIG_PATH was enough for tpm2-tools to
# detect everything it needs. Now, it fails to find "tss2-esys>=2.4.0" and
# suggests setting TSS2_ESYS_2_3_{CFLAGS,LIBS} "to avoid the need to call
# pkg-config". Indeed, setting these works, but those same settings should have
# been picked up from the pkgconfig directory...
HACK_TPM2-TOOLS += PKG_CONFIG_PATH=$(HCP_TPMWARE_INSTALL_DEST)/lib/pkgconfig
HACK_TPM2-TOOLS += TSS2_ESYS_2_3_CFLAGS=\"-I$(HCP_TPMWARE_INSTALL_DEST) -I$(HCP_TPMWARE_INSTALL_DEST)/tss2\"
HACK_TPM2-TOOLS += TSS2_ESYS_2_3_LIBS=\"-L$(HCP_TPMWARE_INSTALL_DEST)/lib -ltss2-esys\"
$(eval $(call builder_add_codebase,\
	tpmware,\
	tpm2-tools,\
	tpm2-tss,\
	tpm2-tools,\
	bootstrap,\
	$(HACK_TPM2-TOOLS) ./bootstrap,\
	$(HACK_TPM2-TOOLS) ./configure --prefix=$(HCP_TPMWARE_INSTALL_DEST),\
	$(HACK_TPM2-TOOLS) make $(HCP_TPMWARE_MAKE_PARALLEL),\
	$(HACK_TPM2-TOOLS) make $(HCP_TPMWARE_MAKE_PARALLEL) install))
$(eval $(call builder_codebase_simpledep,\
	tpmware,\
	tpm2-tools))

endif # HCP_LOCAL_TPM2

# Thus concludes the "tpmware" package
$(eval $(call builder_finalize,tpmware))
