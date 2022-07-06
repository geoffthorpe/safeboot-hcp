HCP_TPMWARE_SRC := $(TOP)/ext-tpmware
HCP_TPMWARE_INSTALL_DEST := /install

# one ring to rule them (tpm-related codebases) ...
$(eval $(call source_builder_initialize,\
	tpmware,\
	install,\
	$(HCP_TPMWARE_INSTALL_DEST),\
	$(HCP_TPMWARE_SUBMODULE_RESET),\
	$(HCP_TPMWARE_SUBMODULE_TARGETS)))

# Only compile-in tpm2-tss and tpm2-tools if we're not using upstream packages
ifdef HCP_TPM2_SOURCE

############
# tpm2-tss #
############

$(eval $(call source_builder_add,\
	tpmware,\
	tpm2-tss,\
	,\
	$(HCP_TPMWARE_SRC)/tpm2-tss,\
	bootstrap,\
	./bootstrap,\
	./configure --disable-doxygen-doc --prefix=$(HCP_TPMWARE_INSTALL_DEST),\
	make $(HCP_TPMWARE_MAKE_PARALLEL),\
	make install))

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
$(eval $(call source_builder_add,\
	tpmware,\
	tpm2-tools,\
	tpm2-tss,\
	$(HCP_TPMWARE_SRC)/tpm2-tools,\
	bootstrap,\
	$(HACK_TPM2-TOOLS) ./bootstrap,\
	$(HACK_TPM2-TOOLS) ./configure --prefix=$(HCP_TPMWARE_INSTALL_DEST),\
	$(HACK_TPM2-TOOLS) make $(HCP_TPMWARE_MAKE_PARALLEL),\
	$(HACK_TPM2-TOOLS) make install))

endif # HCP_TPM2_SOURCE

###########
# libtpms #
###########

$(eval $(call source_builder_add,\
	tpmware,\
	libtpms,\
	,\
	$(HCP_TPMWARE_SRC)/libtpms,\
	autogen.sh,\
	NOCONFIGURE=1 ./autogen.sh,\
	./configure --with-openssl --with-tpm2 --prefix=$(HCP_TPMWARE_INSTALL_DEST),\
	make $(HCP_TPMWARE_MAKE_PARALLEL),\
	make install))

#########
# swtpm #
#########

$(eval $(call source_builder_add,\
	tpmware,\
	swtpm,\
	libtpms,\
	$(HCP_TPMWARE_SRC)/swtpm,\
	autogen.sh,\
	NOCONFIGURE=1 ./autogen.sh,\
	LIBTPMS_LIBS='-L$(HCP_TPMWARE_INSTALL_DEST)/lib -ltpms' \
		LIBTPMS_CFLAGS='-I$(HCP_TPMWARE_INSTALL_DEST)/include' \
		./configure --with-openssl --with-tpm2 \
			--prefix=$(HCP_TPMWARE_INSTALL_DEST),\
	make $(HCP_TPMWARE_MAKE_PARALLEL),\
	make install))

# Only compile-in heimdal if we're not using upstream packages
ifdef HCP_HEIMDAL_SOURCE

###########
# heimdal #
###########

$(eval $(call source_builder_add,\
	tpmware,\
	heimdal,\
	,\
	$(HCP_TPMWARE_SRC)/heimdal,\
	autogen.sh,\
	./autogen.sh,\
	MAKEINFO=true ./configure --prefix=$(HCP_TPMWARE_INSTALL_DEST) --disable-texinfo,\
	MAKEINFO=true make $(HCP_TPMWARE_MAKE_PARALLEL),\
	MAKEINFO=true make install))

endif # HCP_HEIMDAL_SOURCE

# ... and in the darkness, bind them
$(eval $(call source_builder_finalize,tpmware))
