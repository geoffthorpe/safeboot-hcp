HCP_BUILDER_SRC := $(HCP_SRC)/builder
HCP_BUILDER_OUT := $(HCP_OUT)/builder
HCP_BUILDER_DNAME := $(call HCP_IMAGE,builder)

$(HCP_BUILDER_OUT): | $(HCP_OUT)
MDIRS += $(HCP_BUILDER_OUT)

# A wrapper target to build the "builder" image
builder: $(HCP_BUILDER_OUT)/built
ALL += $(HCP_BUILDER_OUT)/built

# We could turn this into a settings.mk choice, but for now just locally
# hard-code it. It determines whether everything has to get rebuilt if the
# builder itself isn't fully up-to-date. E.g. if you touch this Makefile, the
# builder image gets updated by dependency - do you want everything else that
# has been built _using_ this builder image to be rebuilt because the image got
# updated? Probably not.
LAZY := 1

$(HCP_BUILDER_OUT)/Dockerfile: | $(HCP_BUILDER_OUT)
$(HCP_BUILDER_OUT)/Dockerfile: $(HCP_BUILDER_SRC)/Makefile
$(HCP_BUILDER_OUT)/Dockerfile: $(HCP_BUILDER_SRC)/Dockerfile
$(HCP_BUILDER_OUT)/Dockerfile:
	$Qecho "FROM $(HCP_BASE_DNAME)" > $@
	$Qcat $(HCP_BUILDER_SRC)/Dockerfile >> $@

$(HCP_BUILDER_OUT)/deb_src_ify.sh: | $(HCP_BUILDER_OUT)
$(HCP_BUILDER_OUT)/deb_src_ify.sh: $(HCP_BUILDER_SRC)/deb_src_ify.sh
$(HCP_BUILDER_OUT)/deb_src_ify.sh:
	$Qcp $< $@

$(HCP_BUILDER_OUT)/built: $(HCP_BUILDER_OUT)/Dockerfile
$(HCP_BUILDER_OUT)/built: $(HCP_BUILDER_OUT)/deb_src_ify.sh
$(HCP_BUILDER_OUT)/built: $(HCP_BASE_TOUCHFILE)
$(HCP_BUILDER_OUT)/built:
	$Qecho "Building container image $(HCP_BUILDER_DNAME)"
	$Qdocker build -t $(HCP_BUILDER_DNAME) \
	               -f $(HCP_BUILDER_OUT)/Dockerfile \
	               $(HCP_BUILDER_OUT)
	$Qtouch $@
$(eval $(call pp_rule_docker_image_rm,\
	$(HCP_BUILDER_OUT)/built,\
	$(HCP_BUILDER_DNAME),\
	builder,\
	clean_builder))

# Cleanup
ifneq (,$(wildcard $(HCP_BUILDER_OUT)))
clean_builder: | preclean
	$Qrm -f $(HCP_BUILDER_OUT)/Dockerfile $(HCP_BUILDER_OUT)/deb_src_ify.sh
	$Qrmdir $(HCP_BUILDER_OUT)
clean_base: clean_builder
endif

# $1 = package name, used in naming dependency targets, docker volumes, etc.
# $2 = tarball name, often $2==$1.
# $3 = installation path/prefix for all assets installed by the package (and
#      mount point for the volume used to house them, so anything installed
#      anywhere else gets deliberately lost). Note, this must begin with "/".
# $4 = if non-empty, enable "submodule reset" on this codebase. I.e. assume
#      it's a git submodule and should be forcefully reset to current git
#      version (removing all source modifications and build artifacts) when
#      running the corresponding "reset" Makefile target.
# $5 = if non-empty, enabled "extra targets" on this codebase. I.e. fine-grain
#      bootstrap/configure/compile/install targets for each codebase.
# $6 = if non-empty, a specific "builder" container to use, rather than the
#      default: $(HCP_BUILDER_DNAME).
# Note, HCP_BUILD_RESULT_{TGZ,DFILE}_$N are the paths to the resulting
# tarball/Dockerfile.
define builder_initialize
$(eval N := $(strip $1))
$(eval HCP_BUILD_OUT_$N := $(HCP_OUT)/pkg_$N)
$(eval HCP_BUILD_INSTALL_VOLUME_$N := $(HCP_IMAGE_PREFIX)_v$N)
$(eval HCP_BUILD_INSTALL_TOUCH_$N := $(HCP_BUILD_OUT_$N)/vol.created)
$(eval HCP_BUILD_TGZ_$N := $N)
$(eval HCP_BUILD_SRC_$N := $(strip $2))
$(eval HCP_BUILD_INSTALL_DEST_$N := $(strip $3))
$(eval HCP_BUILD_RESET_$N := $(strip $4))
$(eval HCP_BUILD_XTRATARGETS_$N := $(strip $5))
$(eval LOCAL_BUILD_BUILDER_$N := $(strip $6))
$(if $(LOCAL_BUILD_BUILDER_$N),
$(eval HCP_BUILD_BUILDER_$N := $(LOCAL_BUILD_BUILDER_$N))
,
$(eval HCP_BUILD_BUILDER_$N := $(HCP_BUILDER_DNAME)))
$(eval HCP_BUILD_RESULT_PREFIX_$N := $(HCP_BUILD_OUT_$N)/$(HCP_BUILD_TGZ_$N))
$(eval HCP_BUILD_RESULT_TGZ_$N := $(HCP_BUILD_RESULT_PREFIX_$N).tar.gz)
$(HCP_BUILD_OUT_$N): | $(HCP_OUT)
MDIRS += $(HCP_BUILD_OUT_$N)
$(HCP_BUILD_INSTALL_TOUCH_$N): | $(HCP_BUILD_OUT_$N)
	$Qdocker volume create $(HCP_BUILD_INSTALL_VOLUME_$N)
	$Qtouch $$@
$(eval HCP_BUILD_DOCKER_RUN_$N := \
	docker run -i --rm --init --label $(HCP_IMAGE_PREFIX)all=1 \
	--mount type=volume,source=$(HCP_BUILD_INSTALL_VOLUME_$N),destination=$(HCP_BUILD_INSTALL_DEST_$N))
ifneq (,$(LAZY))
HCP_BUILD_BUILDER_DEP_$N := | $(HCP_BUILDER_OUT)/built
else
HCP_BUILD_BUILDER_DEP_$N := $(HCP_BUILDER_OUT)/built
endif
endef

# $1 = name, as per builder_initialize
define builder_finalize
$(eval N := $(strip $1))
$(eval HCP_BUILD_INSTALL_RUN_$N := $(HCP_BUILD_DOCKER_RUN_$N) \
	--mount type=bind,source=$(HCP_BUILD_OUT_$N),destination=/put_it_here \
	$(HCP_BUILD_BUILDER_$N) \
	bash -c)
$(eval HCP_BUILD_TGZ_CMD_$N := cd /put_it_here ;)
$(eval HCP_BUILD_TGZ_CMD_$N += tar zcf $(HCP_BUILD_TGZ_$N).tar.gz $(HCP_BUILD_INSTALL_DEST_$N) ;)
$(eval HCP_BUILD_TGZ_CMD_$N += /hcp/base/chowner.sh vol.created $(HCP_BUILD_TGZ_$N).tar.gz)
$(HCP_BUILD_RESULT_TGZ_$N): $(foreach i,$(HCP_BUILD_MODULES_$N),$(HCP_BUILD_OUT_$N)/$i.installed)
$(HCP_BUILD_RESULT_TGZ_$N):
	$Q$(HCP_BUILD_INSTALL_RUN_$N) "$(HCP_BUILD_TGZ_CMD_$N)"
$N: $(HCP_BUILD_RESULT_TGZ_$N)
ALL += $(HCP_BUILD_RESULT_TGZ_$N)
ifneq (,$(HCP_BUILD_RESET_$N))
$N_reset: $(foreach i,$(HCP_BUILD_RESETS_$N),$(HCP_BUILD_OUT_$N)/$i.reset)
endif
ifneq (,$(wildcard $(HCP_BUILD_OUT_$N)))
ifneq (,$(HCP_BUILD_RESET_$N))
clean_$N: $(foreach i,$(HCP_BUILD_RESETS_$N),$(HCP_BUILD_OUT_$N)/$i.reset)
endif
clean_$N:
	$Qrm -f $(HCP_BUILD_RESULT_TGZ_$N)
ifneq (,$(wildcard $(HCP_BUILD_INSTALL_TOUCH_$N)))
	$Qdocker volume rm $(HCP_BUILD_INSTALL_VOLUME_$N)
	$Qrm $(HCP_BUILD_INSTALL_TOUCH_$N)
endif
	$Qrm -rf $(HCP_BUILD_OUT_$N)
clean_builder: clean_$N
endif
endef

# This instantiates all the support to bootstrap, configure, compile, install,
# and clean a given codebase, named by $2, which is expected to live in $9. Any
# dependencies on other codebases are listed in $3, in which case the the
# configure step for $2 will depend on the install step for each item in $3. $4
# specifies a file that is guaranteed to exist in the top-level directory of
# the codebase prior to bootstrapping, that we can copy user/group ownership
# from. Other arguments provide command lines for the various processing steps
# of the codebase;
# $1 = package name, as passed as $1 to builder_initialize.
# $2 = name of codebase,
# $3 = codebases that must be installed before we can configure.
# $4 = path to source (relative to $2 to builder_initialize)
# $5 = reference file (relative to codebase top-level) for chown-ership of
#      files.
# $6 = command line to bootstrap the codebase
# $7 = command line to configure the codebase
# $8 = command line to compile the codebase
# $9 = command line to install the codebase
# $10 = if non-empty, disable use of "git reset", even if the codebase
#       enables it.
define builder_add_codebase
$(eval N := $(strip $1))
$(eval LOCAL_NAME := $(strip $2))
$(eval LOCAL_DEPS := $(strip $3))
$(eval LOCAL_SRCPATH := $(HCP_BUILD_SRC_$N)/$(strip $4))
$(eval HCP_BUILD_SRC_$N_$(LOCAL_NAME) := $(LOCAL_SRCPATH))
$(eval LOCAL_CHOWNER := $(strip $5))
$(eval LOCAL_CHOWN := trap '/hcp/base/chowner.sh $(LOCAL_CHOWNER) .' EXIT ; cd /src-$(LOCAL_NAME))
$(eval LOCAL_BOOTSTRAP := $(LOCAL_CHOWN) ; $(strip $6))
$(eval LOCAL_CONFIGURE := $(LOCAL_CHOWN) ; $(strip $7))
$(eval LOCAL_COMPILE := $(LOCAL_CHOWN) ; $(strip $8))
$(eval LOCAL_INSTALL := $(LOCAL_CHOWN) ; $(strip $9))
$(eval LOCAL_RESET_DISABLE := $(strip $(10)))
$(eval HCP_BUILD_MODULES_$N += $(LOCAL_NAME))
$(eval LOCAL_RUN := $(HCP_BUILD_DOCKER_RUN_$N))
$(eval LOCAL_RUN += --mount type=bind,source=$(LOCAL_SRCPATH),destination=/src-$(LOCAL_NAME))
$(eval LOCAL_RUN += $(HCP_BUILD_BUILDER_$N))
$(eval LOCAL_RUN += bash -c)
$(eval HCP_BUILD_DEP_$N_$(LOCAL_NAME)_BOOTSTRAPPED := $(HCP_BUILD_OUT_$N)/$(LOCAL_NAME).bootstrapped)
$(eval HCP_BUILD_DEP_$N_$(LOCAL_NAME)_CONFIGURED := $(HCP_BUILD_OUT_$N)/$(LOCAL_NAME).configured)
$(eval HCP_BUILD_DEP_$N_$(LOCAL_NAME)_COMPILED := $(HCP_BUILD_OUT_$N)/$(LOCAL_NAME).compiled)
$(eval HCP_BUILD_DEP_$N_$(LOCAL_NAME)_INSTALLED := $(HCP_BUILD_OUT_$N)/$(LOCAL_NAME).installed)
$(HCP_BUILD_DEP_$N_$(LOCAL_NAME)_BOOTSTRAPPED): | $(LOCAL_SRCPATH)/$(LOCAL_CHOWNER)
$(HCP_BUILD_DEP_$N_$(LOCAL_NAME)_BOOTSTRAPPED): $(HCP_BUILD_BUILDER_DEP_$N)
$(HCP_BUILD_DEP_$N_$(LOCAL_NAME)_BOOTSTRAPPED): | $(HCP_BUILD_INSTALL_TOUCH_$N)
$(HCP_BUILD_DEP_$N_$(LOCAL_NAME)_BOOTSTRAPPED):
	$Q$(LOCAL_RUN) "$(LOCAL_BOOTSTRAP)"
	$Qtouch $$@
$(HCP_BUILD_DEP_$N_$(LOCAL_NAME)_CONFIGURED): $(HCP_BUILD_DEP_$N_$(LOCAL_NAME)_BOOTSTRAPPED)
$(foreach i,$(strip $(LOCAL_DEPS)),
$(HCP_BUILD_DEP_$N_$(LOCAL_NAME)_CONFIGURED): $(HCP_BUILD_OUT_$N)/$i.installed
)
$(HCP_BUILD_DEP_$N_$(LOCAL_NAME)_CONFIGURED):
	$Q$(LOCAL_RUN) "$(LOCAL_CONFIGURE)"
	$Qtouch $$@
$(HCP_BUILD_DEP_$N_$(LOCAL_NAME)_COMPILED): $(HCP_BUILD_DEP_$N_$(LOCAL_NAME)_CONFIGURED)
$(HCP_BUILD_DEP_$N_$(LOCAL_NAME)_COMPILED):
	$Q$(LOCAL_RUN) "$(LOCAL_COMPILE)"
	$Qtouch $$@
$(HCP_BUILD_DEP_$N_$(LOCAL_NAME)_INSTALLED): $(HCP_BUILD_DEP_$N_$(LOCAL_NAME)_COMPILED)
$(HCP_BUILD_DEP_$N_$(LOCAL_NAME)_INSTALLED):
	$Q$(LOCAL_RUN) "$(LOCAL_INSTALL)"
	$Qtouch $$@
$(if $(LOCAL_RESET_DISABLE),,
$(HCP_BUILD_OUT_$N)/$(LOCAL_NAME).reset:
	$Q(cd $(LOCAL_SRCPATH) && git clean -f -d -x && git reset --hard)
	$Qrm -f $(HCP_BUILD_OUT_$N)/$(LOCAL_NAME).*
$(eval HCP_BUILD_RESETS_$N += $(LOCAL_NAME))
)
$(if $(HCP_BUILD_XTRATARGETS_$N),
$N_$(LOCAL_NAME): $(HCP_BUILD_DEP_$N_$(LOCAL_NAME)_INSTALLED)
$N_$(LOCAL_NAME)_bootstrap: $(HCP_BUILD_DEP_$N_$(LOCAL_NAME)_BOOTSTRAPPED)
$N_$(LOCAL_NAME)_configure: $(HCP_BUILD_DEP_$N_$(LOCAL_NAME)_CONFIGURED)
$N_$(LOCAL_NAME)_compile: $(HCP_BUILD_DEP_$N_$(LOCAL_NAME)_COMPILED)
$N_$(LOCAL_NAME)_install: $(HCP_BUILD_DEP_$N_$(LOCAL_NAME)_INSTALLED)
$N_$(LOCAL_NAME)_reset: $(HCP_BUILD_OUT_$N)/$(LOCAL_NAME).reset
)
endef

# Once builder_add_codebase() is run, there are "HCP_BUILD_DEP_a_b_state"
# make targets defined for each package name 'a', codebase 'b', and "state" as
# one of {"BOOTSTRAPPED", "CONFIGURED", "COMPILED", "INSTALLED"}, and these
# targets are actual touchfiles. As such, after builder_add_codebase() returns,
# the caller can declare dependencies on the source in whatever ways necessary
# to ensure that dependencies on these codebases trigger rebuilds as and when
# required.
#
# The following function can provide a naive dependency rule that helps in many
# cases, especially for autotools-managed (autoconf/automake/libtool/etc)
# codebases which might be otherwise impossible to hook up to their
# auto-generated dependency scheme. It makes the "INSTALLED" target for the
# codebase depend on the newest file in the source directory tree. This acts as
# a hair-trigger to re-run the install rule as soon as anything relevant could
# have conceivably changed, because any filesystem activity at all in that tree
# will cause the codebase's "install" logic to run. This approach does
# assume/require that the source's "install" rule will itself first trigger
# recompilation (or even reconfiguration, or even rebootstrapping) if the state
# of files demand it. This is fortunately true for autotools-managed code
# bases.
# $1 = package name, as passed as $1 to builder_initialize.
# $2 = name of codebase, as passed as $2 to builder_initialize.
define builder_codebase_simpledep
$(eval N := $(strip $1))
$(eval LOCAL_NAME := $(strip $2))
$(eval LOCAL_SRCPATH := $(HCP_BUILD_SRC_$N_$(LOCAL_NAME)))
$(eval LOCAL_nfile := $(shell find $(LOCAL_SRCPATH) -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -f2- -d" "))
$(HCP_BUILD_DEP_$N_$(LOCAL_NAME)_INSTALLED): $(LOCAL_nfile)
endef
