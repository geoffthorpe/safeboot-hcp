$(eval $(call app_add,caboodle,include,644,common.sh))
$(eval $(call app_finalize,caboodle))
$(eval $(call app_image,caboodle,common,policysvc enrollsvc attestsvc swtpmsvc kdc tools caboodle,\
	$(HCP_BUILD_RESULT_PREFIX_xtra)))
