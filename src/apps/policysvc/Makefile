$(eval $(call app_add,policysvc,scripts,755,*.sh *.py))
$(eval $(call app_finalize,policysvc))
$(eval $(call app_image,policysvc,common,policysvc,\
	$(HCP_BUILD_RESULT_PREFIX_xtra)))
