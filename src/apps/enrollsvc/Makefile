$(eval $(call app_add,enrollsvc,scripts,755,*.sh *.py))
$(eval $(call app_add,enrollsvc,genprogs,755,genprogs/*))
$(eval $(call app_finalize,enrollsvc))
$(eval $(call app_image,enrollsvc,common,enrollsvc swtpmsvc tools,\
	$(HCP_EXT_RESULT_PREFIX_xtra)))
