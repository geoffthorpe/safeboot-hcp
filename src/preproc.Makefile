# A bunch of cleanup rules were repeating the same dance of checking whether a
# certain touchfile existed to indicated that an image had been built, and if
# so, declaring a rule to clean out the image and touchfile, and making that
# rule a dependency of a parent rule. This function sucks out the noise.
# $1=touchfile
# $2=image
# $3=unique id (must be different each time this is called)
# $4=parent clean rule
define pp_rule_docker_image_rm
	$(eval rname := clean_image_$(strip $3))
	$(eval pname := $(strip $4))
	$(eval tpath := $(strip $1))
	$(eval iname := $(strip $2))
ifneq (,$(wildcard $(tpath)))
$(pname): $(rname)
$(rname):
	$Qecho "Removing container image $(iname)"
	$Qdocker image rm $(iname)
	rm $(strip $(tpath))
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
$(eval oldlist := $(strip $1))
$(eval newlist :=)
$(eval recurse_limit = x$(strip $(recurse_limit)))
$(foreach i,$(oldlist),
	$(if $($i_DEPENDS),
		$(foreach j,$($i_DEPENDS),
			$(if $(or $(filter $j,$(oldlist)),$(filter $j,$(newlist))),,
				$(eval newlist += $j))))
	$(eval newlist += $i))
$(if $(and $(findstring $(oldlist),$(newlist)),
		$(findstring $(newlist),$(oldlist))),,
	$(if $(filter xxxx,$(recurse_limit)),,
	$(eval $(call expand_depends_subrecursive,$(newlist)))))
endef

define expand_depends
$(eval name := $(strip $1))
$(eval list := $($(name)))
$(eval recurse_limit := )
$(eval $(call expand_depends_subrecursive,$(list)))
$(eval $(name) := $(newlist))
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
#      be made a top-level layer (underneath $(HCP_OUT), for example).
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
# $7 - optional, path to a codebase whose package-building dependencies (per
#      its debian/control file) should be added to $4.
#
# Silly choice (please forgive): 'ancestor' represents the layer we are deriving
# from, in docker terms. 'parent' represents the directory we are beneath, in
# file system terms. The new layer is dependent on both.

define pp_add_layer
$(eval upper_name := $(strip $1))
$(eval lower_name := $(shell echo "$(upper_name)" | tr '[:upper:]' '[:lower:]'))
$(eval upper_ancestor := $(strip $2))
$(eval lower_ancestor := $(shell echo "$(upper_ancestor)" | tr '[:upper:]' '[:lower:]'))
$(eval upper_parent := $(strip $3))
$(eval lower_parent := $(shell echo "$(upper_parent)" | tr '[:upper:]' '[:lower:]'))
$(eval pkg_list := $(strip $4))
$(eval dfile_xtra := $(strip $5))
$(eval mfile_xtra := $(strip $6))
$(eval codebase := $(strip $7))

$(eval parent_dir := $(if $(upper_parent),$(HCP_$(upper_parent)_OUT),$(HCP_OUT)))
$(eval parent_clean := $(if $(upper_parent),clean_$(lower_parent),clean))
$(eval out_dir := $(parent_dir)/$(lower_name))
$(eval out_dname := $(call HCP_IMAGE,$(lower_name)))
$(eval out_tfile := $(out_dir)/built)
$(eval out_dfile := $(out_dir)/Dockerfile)

$(eval HCP_$(upper_name)_OUT := $(out_dir))

$(out_dir): | $(parent_dir)
$(eval MDIRS += $(out_dir))

# A wrapper target to build the "$(lower_name)" image
$(lower_name): $(out_dir)/built
$(eval ALL += $(out_dir)/built)

# Symbolic handles this layer should define
$(eval HCP_$(upper_name)_DNAME := $(out_dname))
$(eval HCP_$(upper_name)_TFILE := $(out_tfile))
$(eval HCP_$(upper_name)_DFILE := $(out_dfile))

# And references to our docker ancestor.
$(eval HCP_$(upper_name)_ANCESTOR := HCP_$(upper_ancestor))
$(eval HCP_$(upper_name)_ANCESTOR_DNAME := $($(HCP_$(upper_name)_ANCESTOR)_DNAME))
$(eval HCP_$(upper_name)_ANCESTOR_TFILE := $($(HCP_$(upper_name)_ANCESTOR)_TFILE))

# If we're given a codebase, include its package-building requirements
$(if $(codebase),$(eval pkg_list += \
	$(shell $(HCP_DEBBUILDER_SRC)/get_build_deps.py $(codebase) "")))

# Split the requested packages into those that are(n't) locally-built.
$(eval pkgs_local := $(foreach i,$(pkg_list),$(if $($i_LOCAL_FILE),$i)))
$(eval pkgs_nonlocal := $(foreach i,$(pkg_list),$(if $($i_LOCAL_FILE),,$i)))

# OK, the tricky bit. For any locally-built packages, we need to explicitly
# follow any *_DEPENDS attributes to explicitly install locally-built packages
# that are dependencies. That's the "expand_depends" stuff above.
$(eval $(call expand_depends,pkgs_local))

# For each local package, add a dependency for the package file to be copied to
# the context area for our layer.
$(foreach i,$(pkgs_local),
$(out_dir)/$($i_LOCAL_FILE): | $(out_dir)
$(out_dir)/$($i_LOCAL_FILE): $($i_TFILE)
$(out_dir)/$($i_LOCAL_FILE):
	$Qcp $($i_LOCAL_PATH) $(out_dir)/$($i_LOCAL_FILE)
$(eval pkgs_local_copied += $(out_dir)/$($i_LOCAL_FILE)))

# For local packages, do the shell-fu to prepare commands to the dockerfile;
# - COPY and RUN commands for installing locally-built packages
# - RUN commands for installing upstream packages
# - a path to unconditionally append to the Dockerfile (given that the
#   corresponding parameter is optional)
$(eval pkgs_local_file := $(foreach i,$(pkgs_local),$($i_LOCAL_FILE)))
$(eval pkgs_local_path := $(foreach i,$(pkgs_local),/$($i_LOCAL_FILE)))
$(if $(strip $(pkgs_local)),
	$(eval pkgs_local_cmd1 := COPY $(pkgs_local_file) /)
	$(eval pkgs_local_cmd2 := RUN apt install -y $(pkgs_local_path) && \
			rm -f $(pkgs_local_path))
,
	$(eval pkgs_local_cmd1 := RUN echo no local packages to copy)
	$(eval pkgs_local_cmd2 := RUN echo no local packages to install)
)
$(if $(strip $(pkgs_nonlocal)),
	$(eval pkgs_nonlocal_cmd := RUN apt-get install -y $(pkgs_nonlocal))
,
	$(eval pkgs_nonlocal_cmd := RUN echo no upstream packages to install)
)
$(if $(dfile_xtra),
	$(eval new_dfile_xtra := $(dfile_xtra))
,
	$(eval new_dfile_xtra := /dev/null)
)

# Rule to produce the dockerfile
$(out_dfile): | $(out_dir)
$(out_dfile): $(dfile_xtra) $(mfile_xtra)
$(out_dfile):
	$Qecho "FROM $(HCP_$(upper_name)_ANCESTOR_DNAME)" > $$@
	$Qecho "$(pkgs_local_cmd1)" >> $$@
	$Qecho "$(pkgs_local_cmd2)" >> $$@
	$Qecho "$(pkgs_nonlocal_cmd)" >> $$@
	$Qcat $(new_dfile_xtra) >> $$@

# Rule to build the docker image
$(out_tfile): $(out_dfile)
$(out_tfile): $(HCP_$(upper_name)_ANCESTOR_TFILE)
$(out_tfile): $(pkgs_local_copied)
	$Qecho "Building container image $(out_dname)"
	$Qdocker build -t $(out_dname) \
	               -f $(out_dfile) \
	               $(out_dir)
	$Qtouch $$@

# Cleanup
$(eval $(call pp_rule_docker_image_rm,\
	$(out_tfile),\
	$(out_dname),\
	$(lower_name),\
	clean_$(lower_name)))

ifneq (,$(wildcard $(out_dir)))
clean_$(lower_name): | preclean
	$Qrm -f $(out_dfile) $(out_tfile) \
		$(pkgs_local_copied)
	$Qrmdir $(out_dir)
clean_image_$(lower_ancestor): clean_$(lower_name)
$(parent_clean): clean_$(lower_name)
endif

endef
