$(eval $(call app_add,common,scripts,755,*.sh))
$(eval $(call app_finalize,common))
$(eval $(call app_image,common,,common,\
	$(HCP_BUILD_RESULT_PREFIX_tpmware) \
	$(HCP_BUILD_RESULT_PREFIX_heimdal) \
	$(HCP_BUILD_RESULT_PREFIX_safeboot)))
