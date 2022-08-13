HCP_TOOLS_SRC := $(TOP)/src/tools
HCP_TOOLS_INSTALL_DEST := /hcp/tools

$(eval $(call builder_initialize,\
	tools,\
	$(HCP_TOOLS_SRC),\
	$(HCP_TOOLS_INSTALL_DEST),,))

$(eval $(call builder_add_codebase,\
	tools,\
	tools,\
	,\
	.,\
	Makefile,\
	true,\
	true,\
	true,\
	install *.sh *.py $(HCP_TOOLS_INSTALL_DEST),\
	))
$(eval $(call builder_codebase_simpledep,\
	tools,\
	tools))

$(eval $(call builder_finalize,tools))
