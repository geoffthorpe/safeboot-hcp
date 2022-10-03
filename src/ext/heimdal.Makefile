HCP_HEIMDAL_SRC := $(TOP)/ext-heimdal
HCP_HEIMDAL_INSTALL_DEST := /install-heimdal

# Only compile-in heimdal if we're not using upstream packages
ifdef HCP_HEIMDAL_SOURCE

# We steal the TPMWARE settings as to whether or not enable the
# SUBMODULE_{RESET,TARGETS} options
$(eval $(call builder_initialize,\
	heimdal,\
	$(HCP_HEIMDAL_SRC),\
	$(HCP_HEIMDAL_INSTALL_DEST),\
	$(HCP_TPMWARE_SUBMODULE_RESET),\
	$(HCP_TPMWARE_SUBMODULE_TARGETS)))

$(eval $(call builder_add_codebase,\
	heimdal,\
	heimdal,\
	,\
	.,\
	autogen.sh,\
	./autogen.sh,\
	MAKEINFO=true ./configure --prefix=$(HCP_HEIMDAL_INSTALL_DEST) --disable-texinfo CFLAGS=\"-O0 -g -ggdb3\",\
	MAKEINFO=true make $(HCP_BUILDER_MAKE_PARALLEL),\
	MAKEINFO=true make $(HCP_BUILDER_MAKE_PARALLEL) install))

$(eval $(call builder_codebase_simpledep,\
	heimdal,\
	heimdal))

# Closing arguments for the package
$(eval $(call builder_finalize,heimdal))

endif # HCP_HEIMDAL_SOURCE
