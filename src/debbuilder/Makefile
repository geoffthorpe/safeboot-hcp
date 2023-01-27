HCP_DEBBUILDER_SRC := $(HCP_SRC)/debbuilder
HCP_DEBBUILDER_OUT := $(HCP_OUT)/debbuilder

# Although the directory sits below HCP_OUT, we want the cleanup dependency to
# act as though it was a child of HCP_BASE_OUT.
$(HCP_DEBBUILDER_OUT): | $(HCP_BASE_OUT)
MDIRS += $(HCP_DEBBUILDER_OUT)

# A wrapper target to build the "debbuilder" image
debbuilder: $(HCP_DEBBUILDER_OUT)/built
ALL += $(HCP_DEBBUILDER_OUT)/built

HCP_DEBBUILDER_DNAME := $(call HCP_IMAGE,debbuilder)
HCP_DEBBUILDER_TFILE := $(HCP_DEBBUILDER_OUT)/built
HCP_DEBBUILDER_DFILE := $(HCP_DEBBUILDER_OUT)/Dockerfile

HCP_DEBBUILDER_ANCESTOR := HCP_BASE
HCP_DEBBUILDER_ANCESTOR_DNAME := $($(HCP_DEBBUILDER_ANCESTOR)_DNAME)
HCP_DEBBUILDER_ANCESTOR_TFILE := $($(HCP_DEBBUILDER_ANCESTOR)_TFILE)

$(HCP_DEBBUILDER_DFILE): | $(HCP_DEBBUILDER_OUT)
$(HCP_DEBBUILDER_DFILE): $(HCP_DEBBUILDER_SRC)/Makefile
$(HCP_DEBBUILDER_DFILE): $(HCP_DEBBUILDER_SRC)/Dockerfile
$(HCP_DEBBUILDER_DFILE):
	$Qecho "FROM $(HCP_DEBBUILDER_ANCESTOR_DNAME)" > $@
	$Qcat $(HCP_DEBBUILDER_SRC)/Dockerfile >> $@

$(HCP_DEBBUILDER_TFILE): $(HCP_DEBBUILDER_DFILE)
$(HCP_DEBBUILDER_TFILE): $(HCP_DEBBUILDER_ANCESTOR_TFILE)
$(HCP_DEBBUILDER_TFILE):
	$Qecho "Building container image $(HCP_DEBBUILDER_DNAME)"
	$Qdocker build -t $(HCP_DEBBUILDER_DNAME) \
	               -f $(HCP_DEBBUILDER_DFILE) \
	               $(HCP_DEBBUILDER_OUT)
	$Qtouch $@
$(eval $(call pp_rule_docker_image_rm,\
	$(HCP_DEBBUILDER_TFILE),\
	$(HCP_DEBBUILDER_DNAME),\
	debbuilder,\
	clean_debbuilder))

# Cleanup
ifneq (,$(wildcard $(HCP_DEBBUILDER_OUT)))
clean_debbuilder: | preclean
	$Qrm -f $(HCP_DEBBUILDER_DFILE)
	$Qrmdir $(HCP_DEBBUILDER_OUT)
clean_base: clean_debbuilder
endif

# Images that use deb packages may want locally-built (debbuilder-based)
# packages _or_ upstream packages, and certainly not both. The hcp_dbb() function
# exists to help. You call it per;
#    hcp_dbb(pkglist, ctxpath, cleanupdepvar, builddepvar)
# where;
#  - 'pkglist' is an ordered list of package names that the caller wants
#    installed by their resulting Dockerfile. (Eg. "gawk libjpeg-tools")
#  - 'ctxpath' is the path to the context area that gets used when building the
#     caller's image. The function will create dependencies to populate that area
#     with (hardlinks to) any locally-built packages.
#  - 'cleanupdepvar' is the _name_ of a variable, any locally-built packages
#    that are copied to the 'ctxpath' context area, will have their
#    (destination) paths added to this variable so that cleanup code can remove
#    them.
#  - 'builddepvar' is the _name_ of a variable, for any locally-built packages
#    that are copied and used, the corresponding _touchfile_ for the build of
#    that package is added to this variable. (Multiple locally-built packages
#    may come from the same 'debbuild' and use the same touchfile - the
#    function performs deduplication.)

define hcp_dbb_perpackage
$(eval pkgname := $(strip $1))
$(eval ctxpath := $(strip $2))
$(eval cleanupdepvar := $(strip $3))
$(eval builddepvar := $(strip $4))
$(eval pkgfname := $($(pkgname)_LOCAL_FILE))
$(eval pkgsrc := $($(pkgname)_LOCAL_PATH))
$(eval pkgtfile := $($(pkgname)_TFILE))
$(if $(pkgfname),
$(eval pkgdest := $(ctxpath)/$(pkgfname))
$(pkgdest): | $(ctxpath)
$(pkgdest): $(pkgtfile)
$(pkgdest):
	$Qcp $(pkgsrc) $(pkgdest)
$(eval $(cleanupdepvar) += $(pkgdest))
$(if $(filter $(pkgtfile),$(builddepvar)),,
$(eval $(builddepvar) += $(pkgdest))))
endef

define hcp_dbb
$(eval pkglist := $(strip $1))
$(eval ctxpath := $(strip $2))
$(eval cleanupdepvar := $(strip $3))
$(eval builddepvar := $(strip $4))
$(foreach i,$(pkglist),$(eval $(call hcp_dbb_perpackage,\
	$i,$(ctxpath),$(cleanupdepvar),$(builddepvar))))
endef
