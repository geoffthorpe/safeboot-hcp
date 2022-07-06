HCP_XTRA_SRC := $(TOP)/src/xtra
HCP_XTRA_INSTALL_DEST := /install

$(eval $(call source_builder_initialize,\
	xtra,\
	xtra,\
	$(HCP_XTRA_INSTALL_DEST),,))

$(eval $(call source_builder_add,\
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

$(eval $(call source_builder_finalize,xtra))

