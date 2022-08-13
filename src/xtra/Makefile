HCP_XTRA_SRC := $(TOP)/src/xtra
HCP_XTRA_INSTALL_DEST := /hcp/xtra

$(eval $(call builder_initialize,\
	xtra,\
	$(HCP_XTRA_SRC),\
	$(HCP_XTRA_INSTALL_DEST),,))

$(eval $(call builder_add_codebase,\
	xtra,\
	HcpPython,\
	,\
	.,\
	HcpHostname.py,\
	true,\
	true,\
	true,\
	install --mode=644 *.py $(HCP_XTRA_INSTALL_DEST),\
	))
$(eval $(call builder_codebase_simpledep,\
	xtra,\
	HcpPython))

$(eval $(call builder_finalize,xtra))
