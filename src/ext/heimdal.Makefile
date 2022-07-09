HCP_HEIMDAL_SRC := $(TOP)/ext-heimdal
HCP_HEIMDAL_INSTALL_DEST := /install

# Only compile-in heimdal if we're not using upstream packages
ifdef HCP_HEIMDAL_SOURCE

# We steal the TPMWARE settings as to whether or not enable the
# SUBMODULE_{RESET,TARGETS} options
$(eval $(call ext_builder_initialize,\
	heimdal,\
	heimdal,\
	$(HCP_HEIMDAL_INSTALL_DEST),\
	$(HCP_TPMWARE_SUBMODULE_RESET),\
	$(HCP_TPMWARE_SUBMODULE_TARGETS)))

$(eval $(call ext_builder_add_codebase,\
	heimdal,\
	heimdal,\
	,\
	$(HCP_HEIMDAL_SRC),\
	autogen.sh,\
	./autogen.sh,\
	MAKEINFO=true ./configure --prefix=$(HCP_HEIMDAL_INSTALL_DEST) --disable-texinfo,\
	MAKEINFO=true make $(HCP_BUILDER_MAKE_PARALLEL),\
	MAKEINFO=true make install))

# Thus concludes the "heimdal" package
$(eval $(call ext_builder_finalize,heimdal))

endif # HCP_HEIMDAL_SOURCE
