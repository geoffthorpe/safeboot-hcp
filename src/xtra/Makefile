HCP_XTRA_SRC := $(TOP)/src/xtra
HCP_XTRA_INSTALL_DEST := /hcp/xtra

$(eval $(call ext_builder_initialize,\
	xtra,\
	xtra,\
	$(HCP_XTRA_INSTALL_DEST),,))

$(eval $(call ext_builder_add_codebase,\
	xtra,\
	hcp_expand,\
	,\
	$(HCP_XTRA_SRC),\
	hcp_expand.sh,\
	true,\
	true,\
	true,\
	install hcp_expand.sh $(HCP_XTRA_INSTALL_DEST),\
	))

$(eval $(call ext_builder_finalize,xtra))

