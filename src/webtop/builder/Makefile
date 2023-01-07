HCP_WEBTOPBUILDER_SRC := $(HCP_WEBTOP_SRC)/builder
HCP_WEBTOPBUILDER_OUT := $(HCP_WEBTOP_OUT)/builder
HCP_WEBTOPBUILDER_DNAME := $(call HCP_IMAGE,webtopbuilder)
HCP_WEBTOPBUILDER_DFILE := $(HCP_WEBTOPBUILDER_OUT)/Dockerfile
HCP_WEBTOPBUILDER_TFILE := $(HCP_WEBTOPBUILDER_OUT)/built

$(HCP_WEBTOPBUILDER_OUT): | $(HCP_WEBTOP_OUT)
MDIRS += $(HCP_WEBTOPBUILDER_OUT)

# A wrapper target to build the "webtopbuilder" image
webtopbuilder: $(HCP_WEBTOPBUILDER_TFILE)
ALL += $(HCP_WEBTOPBUILDER_TFILE)

$(HCP_WEBTOPBUILDER_DFILE): | $(HCP_WEBTOPBUILDER_OUT)
$(HCP_WEBTOPBUILDER_DFILE): $(HCP_WEBTOPBUILDER_SRC)/Makefile
$(HCP_WEBTOPBUILDER_DFILE): $(HCP_WEBTOPBUILDER_SRC)/Dockerfile
$(HCP_WEBTOPBUILDER_DFILE):
	$Qecho "FROM $(HCP_WEBTOPBASE_DNAME)" > $@
	$Qcat $(HCP_WEBTOPBUILDER_SRC)/Dockerfile >> $@

# Have WEBTOPBUILDER use the same deb_src_ify.sh as BUILDER
$(HCP_WEBTOPBUILDER_OUT)/deb_src_ify.sh: | $(HCP_WEBTOPBUILDER_OUT)
$(HCP_WEBTOPBUILDER_OUT)/deb_src_ify.sh: $(HCP_BUILDER_SRC)/deb_src_ify.sh
$(HCP_WEBTOPBUILDER_OUT)/deb_src_ify.sh:
	$Qcp $< $@

$(HCP_WEBTOPBUILDER_TFILE): $(HCP_WEBTOPBUILDER_DFILE)
$(HCP_WEBTOPBUILDER_TFILE): $(HCP_WEBTOPBUILDER_OUT)/deb_src_ify.sh
$(HCP_WEBTOPBUILDER_TFILE): $(HCP_WEBTOPBASE_TFILE)
$(HCP_WEBTOPBUILDER_TFILE):
	$Qecho "Building container image $(HCP_WEBTOPBUILDER_DNAME)"
	$Qdocker build -t $(HCP_WEBTOPBUILDER_DNAME) \
	               -f $(HCP_WEBTOPBUILDER_DFILE) \
	               $(HCP_WEBTOPBUILDER_OUT)
	$Qtouch $@
$(eval $(call pp_rule_docker_image_rm,\
	$(HCP_WEBTOPBUILDER_TFILE),\
	$(HCP_WEBTOPBUILDER_DNAME),\
	webtopbuilder,\
	clean_webtopbuilder))

# Cleanup
ifneq (,$(wildcard $(HCP_WEBTOPBUILDER_OUT)))
clean_webtopbuilder: | preclean
	$Qrm -f $(HCP_WEBTOPBUILDER_DFILE) $(HCP_WEBTOPBUILDER_OUT)/deb_src_ify.sh
	$Qrmdir $(HCP_WEBTOPBUILDER_OUT)
clean_webtopbase: clean_webtopbuilder
endif
