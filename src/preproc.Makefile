# A bunch of cleanup rules were repeating the same dance of checking whether a
# certain touchfile existed to indicated that an image had been built, and if
# so, declaring a rule to clean out the image and touchfile, and making that
# rule a dependency of a parent rule. This function sucks out the noise.
# $1=touchfile
# $2=image
# $3=unique id (must be different each time this is called)
# $4=parent clean rule
define pp_rule_docker_image_rm
	$(eval ppr_rname := clean_image_$(strip $3))
	$(eval ppr_pname := $(strip $4))
	$(eval ppr_tpath := $(strip $1))
	$(eval ppr_iname := $(strip $2))
ifneq (,$(wildcard $(ppr_tpath)))
$(ppr_pname): $(ppr_rname)
$(ppr_rname):
	$Qecho "Removing container image $(ppr_iname)"
	$Qdocker image rm $(ppr_iname)
	rm $(strip $(ppr_tpath))
endif
endef

# The following two functions provide a way to form the transitive closure of
# symbols <name> that have <name>_DEPENDS attributes. Eg. if we have the
# following dependencies;
#     bbb_DEPENDS := ddd
#     ccc_DEPENDS := fff
#     ddd_DEPENDS := ggg
#     fff_DEPENDS := ggg
# And if we set;
#     FOOLIST := bbb ccc
# Then calling $(eval $(call expand,FOOLIST)) will result in FOOLIST changing
# to;
#     FOOLIST := ggg ddd bbb fff ccc
# (NB: The parameter is "FOOLIST", not "$(FOOLIST)"!)

define expand_depends_subrecursive
$(eval ppe_oldlist := $(strip $1))
$(eval ppe_newlist :=)
$(eval ppe_recurse_limit = x$(strip $(ppe_recurse_limit)))
$(foreach i,$(ppe_oldlist),
	$(if $($i_DEPENDS),
		$(foreach j,$($i_DEPENDS),
			$(if $(or $(filter $j,$(ppe_oldlist)),$(filter $j,$(ppe_newlist))),,
				$(eval ppe_newlist += $j))))
	$(eval ppe_newlist += $i))
$(if $(and $(findstring $(ppe_oldlist),$(ppe_newlist)),
		$(findstring $(ppe_newlist),$(ppe_oldlist))),,
	$(if $(filter xxxx,$(ppe_recurse_limit)),,
	$(eval $(call expand_depends_subrecursive,$(ppe_newlist)))))
endef

define expand_depends
$(eval ppe_name := $(strip $1))
$(eval ppe_list := $($(ppe_name)))
$(eval ppe_recurse_limit := )
$(eval $(call expand_depends_subrecursive,$(ppe_list)))
$(eval $(ppe_name) := $(ppe_newlist))
endef

# The following wrapper defines a new layer for building a docker image. It
# encapsulates;
# $1 - gives the new layer a symbolic name. This should be upper case, as it
#      will also get converted to lower-case for usage that requires it. E.g.
#      "foo" gives;
#         ./output/apps/foo, make clean_foo, etc.
#         HCP_FOO_OUT, HCP_FOO_DFILE, HCP_FOO_TFILE, etc...
# $2 - the symbolic name (in upper case) of the layer that this layer should be
#      derived from.
# $3 - the symbolic name (in upper case) of the layer whose output directory
#      should be the parent of this layer's output directory. If empty, it will
#      be made a top-level layer (underneath $(HCP_OUT), for example). If $7 is
#      given, then we also assume this layer's source directory is a child of
#      the source directory for the same parent.
# $4 - the packages to be installed in the new layer. For any packages foo that
#      are built locally, foo_LOCAL_FILE should be the path to the resulting
#      package file (and should be a valid makefile target). Locally-built
#      packages should explicitly declare dependencies on other locally-built
#      packages using foo_DEPENDS. The function will expand such dependencies
#      by adding them to the installation layer.
# $5 - optional, a Dockerfile stub to be included in the generated Dockerfile
#      (at the end).
# $6 - optional, path to the caller's Makefile, and/or any other files that
#      should be listed as dependencies for the re-generation of the layer's
#      Dockerfile.
# $7 - an arbitrary number of files in the source directory that should be
#      mirrored to the output directory (and that the build should depend on).
# $8 - an arbitrary number of files with absolute paths that should be mirrored
#      to the output directory (and that the build should depend on).
#
# Silly choice (please forgive): 'ancestor' represents the layer we are deriving
# from, in docker terms. 'parent' represents the directory we are beneath, in
# file system terms. The new layer is dependent on both.

define pp_add_layer
$(eval ppa_name_upper := $(strip $1))
$(eval ppa_name_lower := $(shell echo "$(ppa_name_upper)" | tr '[:upper:]' '[:lower:]'))
$(eval ppa_ancestor_upper := $(strip $2))
$(eval ppa_ancestor_lower := $(shell echo "$(ppa_ancestor_upper)" | tr '[:upper:]' '[:lower:]'))
$(eval ppa_parent_upper := $(strip $3))
$(eval ppa_parent_lower := $(shell echo "$(ppa_parent_upper)" | tr '[:upper:]' '[:lower:]'))
$(eval ppa_pkg_list := $(strip $4))
$(eval ppa_dfile_xtra := $(strip $5))
$(eval ppa_mfile_xtra := $(strip $6))
$(eval ppa_xtra := $(strip $7))
$(eval ppa_xtra_abs := $(strip $8))

$(eval ppa_parent_dir := $(if $(ppa_parent_upper),$(HCP_$(ppa_parent_upper)_OUT),$(HCP_OUT)))
$(eval ppa_parent_clean := $(if $(ppa_parent_upper),clean_$(ppa_parent_lower),clean))
$(eval ppa_parent_src := $(if $(ppa_parent_upper),$(HCP_$(ppa_parent_upper)_SRC),$(HCP_SRC)))
$(eval ppa_out_dir := $(ppa_parent_dir)/$(ppa_name_lower))
$(eval ppa_out_dname := $(call HCP_IMAGE,$(ppa_name_lower)))
$(eval ppa_out_tfile := $(ppa_out_dir)/built)
$(eval ppa_out_dfile := $(ppa_out_dir)/Dockerfile)
$(eval ppa_src := $(ppa_parent_src)/$(ppa_name_lower))
$(eval ppa_copied :=)

$(eval HCP_$(ppa_name_upper)_OUT := $(ppa_out_dir))
$(eval HCP_$(ppa_name_upper)_SRC := $(ppa_src))

$(ppa_out_dir): | $(ppa_parent_dir)
$(eval MDIRS += $(ppa_out_dir))

# A wrapper target to build the "$(ppa_name_lower)" image
$(ppa_name_lower): $(ppa_out_dir)/built
$(eval ALL += $(ppa_out_dir)/built)

# Symbolic handles this layer should define
$(eval HCP_$(ppa_name_upper)_DNAME := $(ppa_out_dname))
$(eval HCP_$(ppa_name_upper)_TFILE := $(ppa_out_tfile))
$(eval HCP_$(ppa_name_upper)_DFILE := $(ppa_out_dfile))

# And references to our docker ancestor.
$(eval HCP_$(ppa_name_upper)_ANCESTOR := HCP_$(ppa_ancestor_upper))
$(eval HCP_$(ppa_name_upper)_ANCESTOR_DNAME := $($(HCP_$(ppa_name_upper)_ANCESTOR)_DNAME))
$(eval HCP_$(ppa_name_upper)_ANCESTOR_TFILE := $($(HCP_$(ppa_name_upper)_ANCESTOR)_TFILE))

# OK, the tricky bit. We need to explicitly follow any *_DEPENDS attributes to
# get transitive closure. This is in order to handle locally-built packages
# depending on other locally-built packages. Ie. this isn't required for
# dependencies on upstream packages, 'apt' installs them as required. But if a
# locally-built package depends on another, and we don't include this in our
# declarative list, we may install the dependent locally-built package but
# 'apt' might satisfy its dependencies with upstream packages rather than the
# locally-built alternatives. The "expand_depends" performs the transitive
# closure, and then we identify and separate out locally-built vs upstream
# packages.
$(eval $(call expand_depends,ppa_pkg_list))
$(eval ppa_pkgs_local := $(foreach i,$(ppa_pkg_list),$(if $($i_LOCAL_FILE),$i)))
$(eval ppa_pkgs_nonlocal := $(foreach i,$(ppa_pkg_list),$(if $($i_LOCAL_FILE),,$i)))

# For each "ppa_xtra" file, add a dependency for it to be copied to the context
# area too.
$(foreach i,$(ppa_xtra),
$(ppa_out_dir)/$i: | $(ppa_out_dir)
$(ppa_out_dir)/$i: $(ppa_src)/$i
$(ppa_out_dir)/$i:
	$Qcp $(ppa_src)/$i $(ppa_out_dir)/$i
$(eval ppa_copied += $(ppa_out_dir)/$i))
# Ditto for "ppa_xtra_abs"
$(foreach i,$(ppa_xtra_abs),
$(eval j := $(shell basename $i))
$(ppa_out_dir)/$j: | $(ppa_out_dir)
$(ppa_out_dir)/$j: $i
$(ppa_out_dir)/$j:
	$Qcp $i $(ppa_out_dir)/$j
$(eval ppa_copied += $(ppa_out_dir)/$j))

# For local packages, do the shell-fu to prepare commands to the dockerfile;
# - COPY and RUN commands for installing locally-built packages
# - RUN commands for installing upstream packages
# - a path to unconditionally append to the Dockerfile (given that the
#   corresponding parameter is optional)
$(eval ppa_pkgs_local_file := $(foreach i,$(ppa_pkgs_local),$($i_LOCAL_FILE)))
$(eval ppa_pkgs_local_path := $(foreach i,$(ppa_pkgs_local),/$($i_LOCAL_FILE)))
$(if $(strip $(ppa_pkgs_local)),
	$(eval ppa_pkgs_local_cmd1 := COPY $(ppa_pkgs_local_file) /)
	$(eval ppa_pkgs_local_cmd2 := RUN apt install -y $(ppa_pkgs_local_path) && \
			rm -f $(ppa_pkgs_local_path))
,
	$(eval ppa_pkgs_local_cmd1 := RUN echo no local packages to copy)
	$(eval ppa_pkgs_local_cmd2 := RUN echo no local packages to install)
)
$(if $(strip $(ppa_pkgs_nonlocal)),
	$(eval ppa_pkgs_nonlocal_cmd := RUN apt-get install -y $(ppa_pkgs_nonlocal))
,
	$(eval ppa_pkgs_nonlocal_cmd := RUN echo no upstream packages to install)
)
$(if $(ppa_dfile_xtra),
	$(eval new_ppa_dfile_xtra := $(ppa_dfile_xtra))
,
	$(eval new_ppa_dfile_xtra := /dev/null)
)

# Rule to produce the dockerfile
$(ppa_out_dfile): | $(ppa_out_dir)
$(ppa_out_dfile): $(ppa_dfile_xtra) $(ppa_mfile_xtra)
$(ppa_out_dfile):
	$Qecho "FROM $(HCP_$(ppa_name_upper)_ANCESTOR_DNAME)" > $$@
	$Qecho "$(ppa_pkgs_local_cmd1)" >> $$@
	$Qecho "$(ppa_pkgs_local_cmd2)" >> $$@
	$Qecho "$(ppa_pkgs_nonlocal_cmd)" >> $$@
	$Qcat $(new_ppa_dfile_xtra) >> $$@

# Rule to build the docker image
$(eval ppa_pkgs_local_src := $(foreach i,$(ppa_pkgs_local),$($i_LOCAL_PATH)))
$(eval ppa_pkgs_local_fnames := $(foreach i,$(ppa_pkgs_local),$($i_LOCAL_FILE)))
$(eval ppa_pkgs_local_tfile :=)
$(foreach i,$(ppa_pkgs_local),
	$(if $(filter $i,$(ppa_pkgs_local_tfile)),,
		$(eval ppa_pkgs_local_tfile += $($i_TFILE))))
$(ppa_out_tfile): $(ppa_out_dfile)
$(ppa_out_tfile): $(HCP_$(ppa_name_upper)_ANCESTOR_TFILE)
$(ppa_out_tfile): $(ppa_pkgs_local_tfile)
$(ppa_out_tfile): $(ppa_copied)
	$Qecho "Building container image $(ppa_out_dname)"
	$Qbash -c " \
	( \
		trap 'cd $(ppa_out_dir) && rm -f $(ppa_pkgs_local_fnames)' EXIT; \
		if [[ -n \"$(ppa_pkgs_local_src)\" ]]; then \
			ln -t $(ppa_out_dir) $(ppa_pkgs_local_src); \
		fi; \
		docker build -t $(ppa_out_dname) -f $(ppa_out_dfile) $(ppa_out_dir); \
	)"
	$Qtouch $$@

# Cleanup
$(eval $(call pp_rule_docker_image_rm,\
	$(ppa_out_tfile),\
	$(ppa_out_dname),\
	$(ppa_name_lower),\
	clean_$(ppa_name_lower)))

ifneq (,$(wildcard $(ppa_out_dir)))
clean_$(ppa_name_lower): | preclean
	$Qrm -f $(ppa_out_dfile) $(ppa_out_tfile) \
		$(ppa_copied)
	$Qrmdir $(ppa_out_dir)
clean_image_$(ppa_ancestor_lower): clean_$(ppa_name_lower)
$(ppa_parent_clean): clean_$(ppa_name_lower)
endif

endef # pp_add_layer()
