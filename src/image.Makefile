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

define __expand_depends_subrecursive
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
	$(eval $(call __expand_depends_subrecursive,$(ppe_newlist)))))
endef

define __expand_depends
$(eval ppe_name := $(strip $1))
$(eval ppe_list := $($(ppe_name)))
$(eval ppe_recurse_limit := )
$(eval $(call __expand_depends_subrecursive,$(ppe_list)))
$(eval $(ppe_name) := $(ppe_newlist))
endef

# hcp_image_derive(): define a docker image.
# $1 - gives the new layer a symbolic name. This should be upper case, as it
#      will get converted to lower-case for usage that requires it. E.g. "foo"
#      gives;
#         ./output/apps/foo, make clean_foo, etc.
#         HCP_FOO_OUT, HCP_FOO_DFILE, HCP_FOO_TFILE, etc...
# $($1_IMG_PARENT)
#      required, the symbolic name (in upper case) of the layer that this layer
#      should be derived from.
# $($1_OUT_PARENT)
#      optional, the symbolic name (in upper case) of the layer whose output
#      directory should be the parent of this layer's output directory. If
#      empty, it will be made a top-level layer underneath $(HCP_OUT).
# $($1_PKGS)
#      optional, the packages to be installed in the new layer.
#      For each package <foo>;
#        If foo_PKG_FORMAT == debbuilder;
#          - foo_LOCAL_FILE should be the path to the package file (and should
#            be a valid makefile target).
#        If foo_PKG_FORMAT == builder;
#          - HCP_BUILD_TGZ_PATH_foo should be the path to the tarball.
#      Locally-built packages should declare their dependencies on other
#      (possibly locally-built) packages using foo_DEPENDS. The function will
#      expand such dependencies and add them to the installation layer. For
#      'debbuilder', this should be set automatically. For 'builder', it's
#      coded.
# $($1_DSTUB)
#      optional, a Dockerfile stub to be included in the generated Dockerfile
#      (at the end).
# $($1_DEPFILES)
#      optional, path to the caller's Makefile and/or any other files that
#      should be listed as dependencies for the re-generation of the layer's
#      Dockerfile.
# $($1_FILES)
#      optional, an arbitrary number of files (with absolute paths) that should
#      be mirrored to the output directory (and that the build will depend on).
#
# Silly choice (please forgive): 'ancestor' represents the layer we are deriving
# from, in docker terms. 'parent' represents the directory we are beneath, in
# file system terms. The new layer is dependent on both.

define hcp_image_derive
$(eval hid_name_upper := $(strip $1))
$(eval hid_name_lower := $(shell echo "$(hid_name_upper)" | tr '[:upper:]' '[:lower:]'))
$(eval hid_ancestor_upper := $(strip $($(hid_name_upper)_IMG_PARENT)))
$(eval hid_ancestor_lower := $(shell echo "$(hid_ancestor_upper)" | tr '[:upper:]' '[:lower:]'))
$(eval hid_parent_upper := $(strip $($(hid_name_upper)_OUT_PARENT)))
$(eval hid_parent_lower := $(shell echo "$(hid_parent_upper)" | tr '[:upper:]' '[:lower:]'))
$(eval hid_pkg_list := $(strip $($(hid_name_upper)_PKGS)))
$(eval hid_dfile_xtra := $(strip $($(hid_name_upper)_DSTUB)))
$(eval hid_mfile_xtra := $(strip $($(hid_name_upper)_DEPFILES)))
$(eval hid_xtra := $(strip $($(hid_name_upper)_FILES)))

$(eval hid_parent_dir := $(if $(hid_parent_upper),$(HCP_$(hid_parent_upper)_OUT),$(HCP_OUT)))
$(eval hid_parent_clean := $(if $(hid_parent_upper),clean_$(hid_parent_lower),clean))
$(eval hid_parent_src := $(if $(hid_parent_upper),$(HCP_$(hid_parent_upper)_SRC),$(HCP_SRC)))
$(eval hid_out_dir := $(hid_parent_dir)/$(hid_name_lower))
$(eval hid_out_dname := $(call HCP_IMAGE_FN,$(hid_name_lower),$(HCP_VARIANT)))
$(eval hid_out_tfile := $(hid_out_dir)/built)
$(eval hid_out_dfile := $(hid_out_dir)/Dockerfile)
$(eval hid_src := $(hid_parent_src)/$(hid_name_lower))
$(eval hid_copied :=)

$(eval HCP_$(hid_name_upper)_OUT := $(hid_out_dir))
$(eval HCP_$(hid_name_upper)_SRC := $(hid_src))

$(hid_out_dir): | $(hid_parent_dir)
$(eval MDIRS += $(hid_out_dir))

# A wrapper target to build the "$(hid_name_lower)" image
$(hid_name_lower): $(hid_out_dir)/built

# Symbolic handles this layer should define
$(eval HCP_$(hid_name_upper)_DNAME := $(hid_out_dname))
$(eval HCP_$(hid_name_upper)_TFILE := $(hid_out_tfile))
$(eval HCP_$(hid_name_upper)_DFILE := $(hid_out_dfile))

# And references to our docker ancestor.
$(eval HCP_$(hid_name_upper)_ANCESTOR := HCP_$(hid_ancestor_upper))
$(eval HCP_$(hid_name_upper)_ANCESTOR_DNAME := $($(HCP_$(hid_name_upper)_ANCESTOR)_DNAME))
$(eval HCP_$(hid_name_upper)_ANCESTOR_TFILE := $($(HCP_$(hid_name_upper)_ANCESTOR)_TFILE))

# OK, the tricky bit. We need to explicitly follow any *_DEPENDS attributes to
# get transitive closure. This is in order to handle locally-built packages
# depending on other locally-built packages. Ie. this isn't required for
# dependencies on upstream packages, 'apt' installs them as required. But if a
# locally-built package depends on another, and we don't include this in our
# declarative list, we may install the dependent locally-built package but
# 'apt' might satisfy its dependencies with upstream packages rather than the
# locally-built alternatives. The "__expand_depends" performs the transitive
# closure, and then we identify and separate out locally-built vs upstream
# packages.
$(eval $(call __expand_depends,hid_pkg_list))
$(eval hid_pkgs_debbuilder :=)
$(eval hid_pkgs_builder :=)
$(eval hid_pkgs_nonlocal :=)
$(foreach i,$(hid_pkg_list),\
$(if $(filter debbuilder,$($i_PKG_FORMAT)),$(eval hid_pkgs_debbuilder += $i),\
$(if $(filter builder,$($i_PKG_FORMAT)),$(eval hid_pkgs_builder += $i),\
$(eval hid_pkgs_nonlocal += $i))))

# For each "hid_xtra" file, add a dependency for it to be copied to the context
# area too.
$(foreach i,$(hid_xtra),
$(eval j := $(shell basename $i))
$(hid_out_dir)/$j: | $(hid_out_dir)
$(hid_out_dir)/$j: $i
$(hid_out_dir)/$j:
	$Qcp $i $(hid_out_dir)/$j
$(eval hid_copied += $(hid_out_dir)/$j))

# For local packages, do the fu to prepare commands for the dockerfile;
# - COPY and RUN commands for installing locally-built packages
# - RUN commands for installing upstream packages
# - a path to unconditionally append to the Dockerfile (given that the
#   corresponding parameter is optional)
$(eval hid_pkgs_deb_file :=)
$(eval hid_pkgs_deb_path :=)
$(eval hid_pkgs_deb_src :=)
$(if $(strip $(hid_pkgs_debbuilder)),
	$(foreach i,$(hid_pkgs_debbuilder),
		$(eval hid_pkgs_deb_file += $($i_LOCAL_FILE))
		$(eval hid_pkgs_deb_path += /$($i_LOCAL_FILE))
		$(eval hid_pkgs_deb_src += $($i_LOCAL_PATH)))
	$(eval hid_pkgs_deb_cmd1 := COPY $(hid_pkgs_deb_file) /)
	$(eval hid_pkgs_deb_cmd2 := RUN \
		$($(hid_name_lower)_INSTALL_PRECMD) apt install -y \
			$(hid_pkgs_deb_path) && \
		rm -f $(hid_pkgs_deb_path))
,
	$(eval hid_pkgs_deb_cmd1 := RUN echo no local deb packages to copy)
	$(eval hid_pkgs_deb_cmd2 := RUN echo no local deb packages to install)
)
$(eval hid_pkgs_tgz_file :=)
$(eval hid_pkgs_tgz_path :=)
$(eval hid_pkgs_tgz_src :=)
$(if $(strip $(hid_pkgs_builder)),
	$(foreach i,$(hid_pkgs_builder),
		$(eval hid_pkgs_tgz_file += $($i_LOCAL_FILE))
		$(eval hid_pkgs_tgz_path += /$($i_LOCAL_FILE))
		$(eval hid_pkgs_tgz_src += $($i_LOCAL_PATH))
		)
	$(eval hid_pkgs_tgz_cmd1 := COPY $(hid_pkgs_tgz_file) /)
	$(eval hid_pkgs_tgz_cmd2 := RUN $(foreach i,$(hid_pkgs_tgz_path),tar zxf $i && ) \
			rm -f $(hid_pkgs_tgz_path))
,
	$(eval hid_pkgs_tgz_cmd1 := RUN echo no local tgz packages to copy)
	$(eval hid_pkgs_tgz_cmd2 := RUN echo no local tgz packages to install)
)
$(if $(strip $(hid_pkgs_nonlocal)),
	$(eval hid_pkgs_nonlocal_cmd := RUN apt-get install -y $(hid_pkgs_nonlocal))
,
	$(eval hid_pkgs_nonlocal_cmd := RUN echo no upstream packages to install)
)
$(if $(hid_dfile_xtra),
	$(eval new_hid_dfile_xtra := $(hid_dfile_xtra))
,
	$(eval new_hid_dfile_xtra := /dev/null)
)

# Rule to produce the dockerfile
$(hid_out_dfile): | $(hid_out_dir)
$(hid_out_dfile): $(hid_dfile_xtra) $(hid_mfile_xtra)
$(hid_out_dfile):
	$Qecho "FROM $(HCP_$(hid_name_upper)_ANCESTOR_DNAME)" > $$@
	$Qecho "$(hid_pkgs_deb_cmd1)" >> $$@
	$Qecho "$(hid_pkgs_deb_cmd2)" >> $$@
	$Qecho "$(hid_pkgs_tgz_cmd1)" >> $$@
	$Qecho "$(hid_pkgs_tgz_cmd2)" >> $$@
	$Qecho "$(hid_pkgs_nonlocal_cmd)" >> $$@
	$Qcat $(new_hid_dfile_xtra) >> $$@

# Rule to build the docker image
$(eval hid_pkgs_local_src := $(strip $(hid_pkgs_deb_src) $(hid_pkgs_tgz_src)))
$(eval hid_pkgs_local_fnames := $(strip $(hid_pkgs_deb_file) $(hid_pkgs_tgz_file)))
$(if $(HCP_DOCKER_EXPERIMENTAL),
	$(eval hid_build_cmd := docker build --squash -t $(hid_out_dname))
,
	$(eval hid_build_cmd := docker build -t $(hid_out_dname))
)
$(eval hid_build_cmd += $(HCP_$(hid_name_upper)_BUILD_ARGS))
$(eval hid_build_cmd += -f $(hid_out_dfile) $(hid_out_dir))
$(if $(hid_pkgs_local_src),
	$(eval hid_pkgs_preamble := \
		trap 'cd $(hid_out_dir) && rm -f $(hid_pkgs_local_fnames)' EXIT; \
		ln -t $(hid_out_dir) $(hid_pkgs_local_src)),
	$(eval hid_pkgs_preamble := /bin/true))
$(hid_out_tfile): $(hid_out_dfile) $(HCP_$(hid_name_upper)_ANCESTOR_TFILE)
$(hid_out_tfile): $(hid_pkgs_local_src) $(hid_copied)
	$Qecho "Building container image $(hid_out_dname)"
	$Qbash -c " \
	( \
		$(hid_pkgs_preamble); \
		$(hid_build_cmd); \
	)"
	$Qtouch $$@

# Cleanup
ifneq (,$(wildcard $(hid_out_tfile)))
clean_$(hid_name_lower): clean_image_$(hid_name_lower)
clean_image_$(hid_name_lower):
	$Qecho "Removing container image $(hid_out_dname)"
	$Qdocker image rm $(hid_out_dname)
	rm $(strip $(hid_out_tfile))
endif

ifneq (,$(wildcard $(hid_out_dir)))
clean_$(hid_name_lower): | preclean
	$Qrm -f $(hid_out_dfile) $(hid_out_tfile) \
		$(hid_copied)
	$Qrmdir $(hid_out_dir)
clean_image_$(hid_ancestor_lower): clean_$(hid_name_lower)
$(hid_parent_clean): clean_$(hid_name_lower)
endif

endef # hcp_image_derive()
