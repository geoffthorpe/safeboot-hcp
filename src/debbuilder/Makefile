HCP_DEBBUILDER_SRC := $(HCP_SRC)/debbuilder

$(eval $(call pp_add_layer,\
	DEBBUILDER,\
	BASE,\
	,\
	build-essential devscripts dpkg-dev,\
	,\
	$(HCP_DEBBUILDER_SRC)/Makefile,\
	,\
	))

# pvt_debian_build() - adds rules to build debian packages. This private function
#      is used by the debian_build() API.
# $1 - name of the package set in lower case.
# $2 - name of the layer used for building these packages (usually created by
#      the pp_add_layer() API just above). The artifacts produced will be put
#      in the 'artifacts' subdirectory of that layer's output directory.
# $3 - the calling Makefile and any other source files that the resulting
#      debian build rules should be dependent on.
#
# Makefile variables are used for the remainder of input to (and output from)
# this function. Assuming $1==FOO, voici;
# Inputs;
#      - foo_PKGS: the short names of the packages produced by this package
#        set. Eg; "libtpms0 libtpms0-dbgsym libtpms-dev"
#      - foo_PKG_SRC: absolute path to the codebase for this package set.
#      - foo_PKG_CMD_BOOTSTRAP: the command to run to ensure that the codebase
#        is ready to be built (like triggering autoconf/automake).
#        Default: "/bin/true"
#      - foo_PKG_CMD_PACKAGE: the command to build the debian packages.
#        Default: "debuild -uc -us"
#      - foo_PKG_SUFFIX: when appended to an individual <pkg> name, gives the
#        expected filename of the resulting package. (Each package can override
#        this with <pkg>_LOCAL_FILE.)
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
#        If this per-package filename is not specified, it will be deduced from
#        foo_PKG_SUFFIX.
# Outputs;
#      - HCP_DBB_LIST: foo_PKGS gets added to this accumulator.
#      - deb_foo: symbolic make target for foo_PKGS, ie. to build the package
#        set.
#      - clean_deb_foo: symbolic make target to remove output associated with
#        this package set.
#      For each <pkg> in foo_PKGS;
#      - <pkg>_LOCAL_PATH: absolute path to the debian package file (whose name
#        is expected to be <pkg>_LOCAL_FILE).

define pvt_debian_build

$(eval dbo_name_lower := $(strip $1))
$(eval dbo_name_upper := $(shell echo "$(dbo_name_lower)" | tr '[:lower:]' '[:upper:]'))
$(eval dbo_layer_upper := $(strip $2))
$(eval dbo_layer_lower := $(shell echo "$(dbo_layer_upper)" | tr '[:upper:]' '[:lower:]'))
$(eval dbo_file_deps := $(strip $3))

# Calculate derivates once
$(eval dbo_parent_dir := $(HCP_$(dbo_layer_upper)_OUT))
$(eval dbo_out_dir := $(dbo_parent_dir)/artifacts-$(dbo_name_lower))
$(eval dbo_mount_dir := $(dbo_out_dir)/$(dbo_name_lower))
$(eval dbo_tfile_bootstrapped := $(dbo_out_dir)/_bootstrapped)
$(eval dbo_tfile_packaged := $(dbo_out_dir)/_packaged)
$(eval dbo_src_dir := $($(dbo_name_lower)_PKG_SRC))
$(eval dbo_layer_upper_dname := $(HCP_$(dbo_layer_upper)_DNAME))
$(eval dbo_cmd_bootstrap := $($(dbo_name_lower)_PKG_CMD_BOOTSTRAP))
$(eval dbo_cmd_package := $($(dbo_name_lower)_PKG_CMD_PACKAGE))
$(eval dbo_builddeps := $($(dbo_name_lower)_PKG_BUILD_DEPENDS))
$(eval dbo_suffix := $($(dbo_name_lower)_PKG_SUFFIX))

$(if $(dbo_cmd_bootstrap),,$(eval dbo_cmd_bootstrap := /bin/true))
$(if $(dbo_cmd_package),,$(eval dbo_cmd_package := debuild -uc -us))

# In addition to the 'Build-Depends' packages, we also want to preinstall any
# run-time dependencies of the individual packages we're installing. However,
# we need to exclude duplicates, and also avoid listing packages that we are
# producing. (If one of our output packages depends on another of our output
# packages, neither of them should be preinstalled!)
$(foreach p,$($(dbo_name_lower)_PKGS),\
	$(foreach d,$($p_DEPENDS),\
		$(if $(filter $d,$(dbo_builddeps)),,\
			$(if $(filter $d,$($(dbo_name_lower)_PKGS)),,\
				$(eval dbo_builddeps += $d)))))

# Derive a layer that will have our deps installed
$(eval dbo_build_layer_upper := $(dbo_layer_upper)_$(dbo_name_upper))
$(eval $(call pp_add_layer,\
	$(dbo_build_layer_upper),\
	$(dbo_layer_upper),\
	$(dbo_layer_upper),\
	$(dbo_builddeps),\
	,\
	$(dbo_file_deps),\
	,\
	))
$(eval dbo_build_layer_dname := $(HCP_$(dbo_build_layer_upper)_DNAME))
$(eval dbo_build_layer_tfile := $(HCP_$(dbo_build_layer_upper)_TFILE))

# Auto-create output directories
$(dbo_out_dir): | $(dbo_parent_dir)
$(dbo_mount_dir): | $(dbo_out_dir)
$(eval MDIRS += $(dbo_out_dir) $(dbo_mount_dir))

# Expected outputs
$(eval HCP_DBB_LIST += $($(dbo_name_lower)_PKGS))
$(eval dbo_local_paths := )
$(foreach p,$($(dbo_name_lower)_PKGS),\
	$(if $($p_LOCAL_FILE),,$(eval $p_LOCAL_FILE := $p$(dbo_suffix)))\
	$(eval $p_LOCAL_PATH := $(dbo_out_dir)/$($p_LOCAL_FILE))\
	$(eval dbo_local_paths += $($p_LOCAL_PATH)))
deb_$(dbo_name_lower): $(dbo_local_paths)
$(eval ALL += deb_$(dbo_name_lower))

# How to launch the image layer
$(eval docker_run := docker run --rm -v $(dbo_out_dir):/empty \
			-v $(dbo_src_dir):/empty/$(dbo_name_lower) \
			-v $(HCP_SRC)/reffile:/reffile:ro \
			$(dbo_build_layer_dname) \
			bash -c)
# and common preamble to what we run in the container
$(eval docker_cmd := trap '/hcp/base/chowner.sh /reffile/reffile ..' EXIT ; \
			cd /empty/$(dbo_name_lower))

# Bootstrap target
$(dbo_tfile_bootstrapped): $(dbo_build_layer_tfile)
$(dbo_tfile_bootstrapped): | $(dbo_mount_dir)
$(dbo_tfile_bootstrapped):
	$Q$(docker_run) "$(docker_cmd) ; $(dbo_cmd_bootstrap)"
	$Qtouch $$@

# Packaging target. This gets set when the packaging is run. This is an
# internal target only, however.  Immediately after this, we create
# dependencies on this packaging target by the package files themselves, which
# is what other code should depend on.
# NB: we add a dependency on the most recent file in the codebase, hence the
# complicated 'find' command.
$(dbo_tfile_packaged): $(dbo_tfile_bootstrapped)
$(dbo_tfile_packaged): $(shell find $(dbo_src_dir) -type f -printf '%T@ %p\n' | \
			sort -n | tail -1 | cut -f2- -d" ")
$(dbo_tfile_packaged):
	$Q$(docker_run) "$(docker_cmd) ; $(dbo_cmd_package)"
	$Qtouch $$@

# Make the debian package files depend on the packaging target that produces
# them. (We confirm that the packaging process produced the expected package,
# then we touch that package so that the dependency won't re-trigger.)
$(foreach p,$($(dbo_name_lower)_PKGS),
$($p_LOCAL_PATH): $(dbo_tfile_packaged)
	$Qif ! test -f $($p_LOCAL_PATH); then \
		echo "Error, package file missing: $($p_LOCAL_PATH)" >&2; \
		exit 1; \
	fi
	$Qtouch $($p_LOCAL_PATH)
)

$(if $(wildcard $(dbo_out_dir)),
clean_deb_$(dbo_name_lower):
	$Qif test -d $(dbo_mount_dir); then rmdir $(dbo_mount_dir); fi
	$Qrm -f $(dbo_out_dir)/*
	$Qrmdir $(dbo_out_dir)
clean_$(dbo_layer_lower): clean_deb_$(dbo_name_lower)
)
endef # debian_build_one

# $1 - prefix for variables with the package set details. Input attributes must
#      be provided using this prefix (_PKG_SRC, _PKG_CMD_{BOOTSTRAP,PACKAGE},
#      _PKG_SUFFIX).
# $2 - name of the layer used for building the package(s)
# $3 - the calling Makefile or anything else this package should depend on
define debian_build
$(eval db_mksym := $(strip $1))
$(eval db_layer_upper := $(strip $2))
$(eval db_file_deps := $(strip $3))
$(eval db_xtra :=)

$(eval db_srcdir := $($(db_mksym)_PKG_SRC))

$(eval db_mkout := $(HCP_OUT)/.mkout.$(db_mksym))
$(eval db_file_deps += $(db_mkout))
clean_mkout_$(db_mksym):
	$Qrm -f $(db_mkout)
clean: clean_mkout_$(db_mksym)

$(eval $(call pp_exec_stdout_to_make,\
	$(HCP_DEBBUILDER_SRC)/parse_debian_control.py $(db_srcdir) | \
	$(HCP_DEBBUILDER_SRC)/mkvars_from_debcontrol.py,\
	$(db_mkout)))

$(eval $(call pvt_debian_build,$(db_mksym),$(db_layer_upper),$(db_file_deps)))

endef # debian_build
