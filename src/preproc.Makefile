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
#      be made a top-level layer (underneath $(HCP_OUT), for example). If $8 is
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
# $7 - optional, path to a codebase whose package-building dependencies (per
#      its debian/control file) should be added to $4.
# $8 - an arbitrary number of files in the source directory that should be
#      mirrored to the output directory (and that the build should depend on).
# $9 - an arbitrary number of files with absolute paths that should be mirrored
#      to the output directory (and that the build should depend on).
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
$(eval xtra := $(strip $8))
$(eval xtra_abs := $(strip $9))

$(eval parent_dir := $(if $(upper_parent),$(HCP_$(upper_parent)_OUT),$(HCP_OUT)))
$(eval parent_clean := $(if $(upper_parent),clean_$(lower_parent),clean))
$(eval parent_src := $(if $(upper_parent),$(HCP_$(upper_parent)_SRC),$(HCP_SRC)))
$(eval out_dir := $(parent_dir)/$(lower_name))
$(eval out_dname := $(call HCP_IMAGE,$(lower_name)))
$(eval out_tfile := $(out_dir)/built)
$(eval out_dfile := $(out_dir)/Dockerfile)
$(eval my_src := $(parent_src)/$(lower_name))
$(eval files_copied :=)

$(eval HCP_$(upper_name)_OUT := $(out_dir))
$(eval HCP_$(upper_name)_SRC := $(my_src))

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

# For each "xtra" file, add a dependency for it to be copied to the context
# area too.
$(foreach i,$(xtra),
$(out_dir)/$i: | $(out_dir)
$(out_dir)/$i: $(my_src)/$i
$(out_dir)/$i:
	$Qcp $(my_src)/$i $(out_dir)/$i
$(eval files_copied += $(out_dir)/$i))
# Ditto for "xtra_abs"
$(foreach i,$(xtra_abs),
$(eval j := $(shell basename $i))
$(out_dir)/$j: | $(out_dir)
$(out_dir)/$j: $i
$(out_dir)/$j:
	$Qcp $i $(out_dir)/$j
$(eval files_copied += $(out_dir)/$j))

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
$(eval pkgs_local_src := $(foreach i,$(pkgs_local),$($i_LOCAL_PATH)))
$(eval pkgs_local_tfile :=)
$(foreach i,$(pkgs_local),
	$(if $(filter $i,$(pkgs_local_tfile)),,
		$(eval pkgs_local_tfile += $($i_TFILE))))
$(out_tfile): $(out_dfile)
$(out_tfile): $(HCP_$(upper_name)_ANCESTOR_TFILE)
$(out_tfile): $(pkgs_local_tfile)
$(out_tfile): $(files_copied)
	$Qecho "Building container image $(out_dname)"
	$Qbash -c \
		"if [[ -n \"$(pkgs_local_src)\" ]]; then \
			ln -t $(out_dir) $(pkgs_local_src); \
		fi"
	$Qdocker build -t $(out_dname) \
	               -f $(out_dfile) \
	               $(out_dir)
	$Qbash -c \
		"if [[ -n \"$(pkgs_local_src)\" ]]; then \
			(cd $(out_dir) && rm -f $(pkgs_local_file)) \
		fi"
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
		$(files_copied)
	$Qrmdir $(out_dir)
clean_image_$(lower_ancestor): clean_$(lower_name)
$(parent_clean): clean_$(lower_name)
endif

endef # pp_add_layer()

# The following wrapper adds rules to build debian packages;
# $1 - name of the package set in upper case. This should be upper case as it
#      will get converted to lower case internally where appropriate. The
#      codebase that produces the packages is usually the lower case value. The
#      inputs required by this function will be prefixed by this name (see
#      below).
# $2 - name of the layer used for building these packages (usually created by
#      the pp_add_layer() API just above). The artifacts produced will be put
#      in the 'artifacts' subdirectory of that layer's output directory.
#
# Makefile variables are used for the remainder of input to (and output from)
# this function. Assuming $1==FOO, voici;
# Inputs;
#      - foo_PKGS: the short names of the packages produced by this package
#        set. Eg; "libtpms0 libtpms0-dbgsym libtpms-dev"
#      - foo_CANONICAL: if, later on, a 'builder'-based image says its needs
#        'libtpms', what subset of foo_PKGS do they mean?
#      - FOO_PKG_SRC: absolute path to the codebase for this package set.
#      - FOO_PKG_REFFILE: path relative to FOO_PKG_SRC, points to an immutable
#        file in the codebase, which is used as a reference when "chown"ing
#        files in mounted directories.
#      - FOO_PKG_CMD_BOOTSTRAP: the command to run to ensure that the codebase
#        is ready to be built (like triggering autoconf/automake). Eg;
#        "./autogen.sh"
#      - FOO_PKG_CMD_PACKAGE: the command to build the debian packages. Eg;
#        "dpkg-buildpackage -uc -us"
#      For each <pkg> in foo_PKGS;
#      - <pkg>_DEPENDS: if <pkg> depends on any other packages that might be
#        locally-built, in this package set or another, this variable should
#        list them. When locally-built packages get installed later on, this
#        declaration helps ensure that locally-built dependencies also get
#        installed rather than upstream versions. Eg;
#          "libtpms-dev_DEPENDS := libtpms0"
#      - <pkg>_LOCAL_FILE: the filename that the resulting debian package
#        is expected to have. The build does not ensure this, the caller is
#        expected to predict it. Eg;
#          "libtpms0_LOCAL_FILE := libtpms0_0.10.0~dev1_amd64.deb"
# Outputs;
#      - HCP_DBB_LIST: foo_PKGS gets added to this accumulator.
#      - HCP_FOO_PKG_BOOTSTRAPPED: absolute path to the touchfile that gets set
#        when the package set is bootstrapped. Can be used as a dependency.
#      - HCP_FOO_PKG_PACKAGED: absolute path to the touchfile that gets set
#        when the package set is built. Can be used as a dependency.
#      - deb_foo: symbolic make target for HCP_FOO_PKG_PACKAGES, ie. to build
#        the package set.
#      - clean_deb_foo: symbolic make target to remove output associated with
#        this package set.
#      For each <pkg> in foo_PKGS;
#      - <pkg>_TFILE: set equal to HCP_FOO_PKG_PACKAGED, which is set when the
#        package set is built. (This isn't package-specific, all the packages
#        in the same set will have the same _TFILE attribute.)
#      - <pkg>_LOCAL_PATH: absolute path to the debian package file (whose name
#        is expected to be <pkg>_LOCAL_FILE).

define pp_add_dpkg_build
$(eval upper_name := $(strip $1))
$(eval lower_name := $(shell echo "$(upper_name)" | tr '[:upper:]' '[:lower:]'))
$(eval upper_layer := $(strip $2))
$(eval lower_layer := $(shell echo "$(upper_layer)" | tr '[:upper:]' '[:lower:]'))

# Calculate paths once
$(eval parent_dir := $(HCP_$(upper_layer)_OUT))
$(eval out_dir := $(parent_dir)/artifacts-$(lower_name))
$(eval mount_dir := $(out_dir)/$(lower_name))
$(eval tfile_bootstrapped := $(out_dir)/_bootstrapped)
$(eval tfile_packaged := $(out_dir)/_packaged)
$(eval src_dir := $($(upper_name)_PKG_SRC))
$(eval layer_dname := $(HCP_$(upper_layer)_DNAME))
$(eval layer_tfile := $(HCP_$(upper_layer)_TFILE))
$(eval reffile := $($(upper_name)_PKG_REFFILE))
$(eval cmd_bootstrap := $($(upper_name)_PKG_CMD_BOOTSTRAP))
$(eval cmd_package := $($(upper_name)_PKG_CMD_PACKAGE))

# Auto-create output directories
$(out_dir): | $(parent_dir)
$(mount_dir): | $(out_dir)
$(eval MDIRS += $(out_dir) $(mount_dir))

# Expected outputs
$(eval HCP_DBB_LIST += $($(lower_name)_PKGS))
$(eval HCP_$(upper_name)_PKG_BOOTSTRAPPED := $(tfile_bootstrapped))
$(eval HCP_$(upper_name)_PKG_PACKAGED := $(tfile_packaged))
deb_$(lower_name): $(tfile_packaged)
$(eval ALL += deb_$(lower_name))
$(foreach p,$($(lower_name)_PKGS),
	$(eval $p_TFILE := $(tfile_packaged))
	$(eval $p_LOCAL_PATH := $(out_dir)/$($p_LOCAL_FILE)))

# How to launch the image layer
$(eval docker_run := docker run --rm -v $(out_dir):/empty \
			-v $(src_dir):/empty/$(lower_name) \
			$(layer_dname) \
			bash -c)
# and common preamble to what we run in the container
$(eval docker_cmd := trap '/hcp/base/chowner.sh $(reffile) ..' EXIT ; \
			cd /empty/$(lower_name))

# Bootstrap target
$(tfile_bootstrapped): $(layer_tfile)
$(tfile_bootstrapped): | $(mount_dir)
$(tfile_bootstrapped):
	$Q$(docker_run) "$(docker_cmd) ; $(cmd_bootstrap)"
	$Qtouch $$@

# Package target. NB: we add a dependency on the most recent file in the
# codebase, hence the complicated 'find' command.
$(tfile_packaged): $(tfile_bootstrapped)
$(tfile_packaged): $(shell find $(src_dir) -type f -printf '%T@ %p\n' | \
			sort -n | tail -1 | cut -f2- -d" ")
$(tfile_packaged):
	$Q$(docker_run) "$(docker_cmd) ; $(cmd_package)"
	$Qtouch $$@

$(if $(wildcard $(out_dir)),
clean_deb_$(lower_name):
	$Qif test -d $(mount_dir); then rmdir $(mount_dir); fi
	$Qrm -f $(out_dir)/*
	$Qrmdir $(out_dir)
clean_$(lower_layer): clean_deb_$(lower_name)
)
endef # pp_add_dpkg_build
