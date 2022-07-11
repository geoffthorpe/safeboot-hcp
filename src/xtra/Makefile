HCP_XTRA_SRC := $(TOP)/src/xtra
HCP_XTRA_INSTALL_DEST := /install

$(eval $(call ext_builder_initialize,\
	xtra,\
	xtra,\
	$(HCP_XTRA_INSTALL_DEST),,))

$(eval $(call ext_builder_add_codebase,\
	xtra,\
	param_expand,\
	,\
	$(HCP_XTRA_SRC),\
	param_expand.c,\
	true,\
	true,\
	gcc -Wall -g -ggdb3 -o param_expand param_expand.c,\
	mkdir -p $(HCP_XTRA_INSTALL_DEST)/bin && cp param_expand $(HCP_XTRA_INSTALL_DEST)/bin,\
	))

$(eval $(call ext_builder_finalize,xtra))

