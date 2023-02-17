HCP_HEIMDAL_SRC := $(TOP)/ext-heimdal
HCP_HEIMDAL_PREFIX := /usr

# Only compile-in heimdal if we're not using upstream packages
ifdef HCP_LOCAL_HEIMDAL

$(eval $(call builder_add,\
	heimdal,\
	$(HCP_HEIMDAL_SRC),\
	,\
	,\
	./autogen.sh,\
	MAKEINFO=true ./configure --disable-texinfo --prefix=$(HCP_HEIMDAL_PREFIX),\
	MAKEINFO=true make $(HCP_BUILDER_MAKE_PARALLEL),\
	MAKEINFO=true make $(HCP_BUILDER_MAKE_PARALLEL) install,\
	))

$(eval $(call builder_simpledep,heimdal))

endif # HCP_LOCAL_HEIMDAL
