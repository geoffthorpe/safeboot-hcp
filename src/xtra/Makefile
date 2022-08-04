HCP_XTRA_SRC := $(TOP)/src/xtra
HCP_XTRA_INSTALL_DEST := /hcp/xtra

$(eval $(call ext_builder_initialize,\
	xtra,\
	xtra,\
	$(HCP_XTRA_INSTALL_DEST),,))

$(eval $(call ext_builder_add_codebase,\
	xtra,\
	HcpPython,\
	,\
	$(HCP_XTRA_SRC),\
	HcpHostname.py,\
	true,\
	true,\
	true,\
	install --mode=64 *.py $(HCP_XTRA_INSTALL_DEST),\
	))

$(eval $(call ext_builder_finalize,xtra))

