$(eval $(call app_add,caboodle,include,644,common.sh))
$(eval $(call app_finalize,caboodle))
$(eval $(call app_image,caboodle,common,enrollsvc attestsvc swtpmsvc kdc tools caboodle,\
	$(HCP_SOURCE_OUT_xtra)/$(HCP_SOURCE_TGZ_xtra)))
