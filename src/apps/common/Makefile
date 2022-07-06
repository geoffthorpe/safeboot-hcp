$(eval $(call app_add,common,scripts,755,*.sh))
$(eval $(call app_finalize,common))
$(eval $(call app_image,common,,common,\
	$(HCP_SOURCE_OUT_tpmware)/$(HCP_SOURCE_TGZ_tpmware) \
	$(HCP_SAFEBOOT_OUT)/safeboot))
