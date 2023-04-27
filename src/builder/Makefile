HCP_BUILDER_SRC := $(HCP_SRC)/builder

# We could turn this into a settings.mk choice, but for now just locally
# hard-code it. It determines whether everything has to get rebuilt if the
# builder itself isn't fully up-to-date. E.g. if you touch this Makefile, the
# builder image gets updated by dependency - do you want everything else that
# has been built _using_ this builder image to be rebuilt because the image got
# updated? Probably not.
LAZY := 1

# We're going to assume that the builder image should have all the
# locally-built packages $(HCP_DBB_LIST) preinstalled. 'builder' is a less
# refined way of building, packaging, and installing. (Globally-unique
# installation path for each package, the package is a tarball, no recording or
# handling of dependencies, ...) So having the builder image preinstall
# everything that might be a dependency is a good way of keeping it simple.
BUILDER_DEPS := $(HCP_DBB_LIST)

# The pp_add_layer() logic, rightly, prioritizes the installation of
# locally-built packages before the installation of upstream packages. This is
# to avoid the case where an upstream package has a dependency on a package we
# have locally-built but that 'apt' pulls an upstream version before we try to
# install the locally-built one. However, here we are installing a large set of
# upstream packages that do not depend on anything we're building, and if they
# install after our locally-built packages, then they will be redownloaded and
# reinstalled every time we make local changes, without any fancy docker (and
# buildkit) caching to speed it up.
# --> Solution: use two layers.
$(eval $(call pp_add_layer,\
	PREBUILDER,\
	BASE,\
	,\
	gcc g++ make \
		automake autoconf autoconf-archive libtool pkg-config \
		expect gawk socat help2man bison flex \
		libc-dev libssl-dev libseccomp-dev libtasn1-6-dev \
		libjson-c-dev libcurl4-openssl-dev libqrencode-dev \
		uuid-dev gnu-efi binutils-dev libjson-glib-dev \
		libfile-slurp-perl libncurses5-dev comerr-dev libdb-dev,\
	$(HCP_BUILDER_SRC)/Dockerfile,\
	$(HCP_BUILDER_SRC)/Makefile,\
	,\
	$(HCP_BUILDER_SRC)/deb_src_ify.sh))
$(eval $(call pp_add_layer,\
	BUILDER,\
	PREBUILDER,\
	,\
	$(BUILDER_DEPS),\
	,\
	$(HCP_BUILDER_SRC)/Makefile,\
	,\
	))

# $1 = package name, used in naming the build layer, dependency targets, etc.
# $2 = path to source
# $3 = packages that are build dependencies.
# $4 = packages that are run-time dependencies.
# $5 = extra option arguments to 'docker run' (eg. mounts)
# $1_CMD_BOOTSTRAP = command line to bootstrap the codebase
# $1_CMD_CONFIGURE = command line to configure the codebase
# $1_CMD_COMPILE = command line to compile the codebase
# $1_CMD_INSTALL = command line to install the codebase
# $1_BUILDER = alternative builder layer to the default; "BUILDER". If specified
#              it should probably be a derivative of "BUILDER".
# Once builder_add() is run;
# - $1_BUILT_PATH is the path to the resulting tarball.
# - If a cached package is available, $1_LOCAL_PATH points to that, otherwise
#   it points to $1_BUILT_PATH. Dependencies should use $1_LOCAL_PATH in order
#   to respect the configured cache options.
# - HCP_BUILD_DEP_<pkg>_<state> targets are defined for each <state> as one of
#   {"BOOTSTRAPPED", "CONFIGURED", "COMPILED", "INSTALLED"}, and these targets
#   are actual touchfiles. As such, the caller can declare dependencies in
#   whatever ways necessary to ensure that dependencies on these codebases
#   trigger rebuilds as and when required.
define builder_add
$(eval N_lower := $(strip $1))
$(eval N := $(shell echo "$(N_lower)" | tr '[:lower:]' '[:upper:]'))
$(eval HCP_BUILD_SRC_$N := $(strip $2))
$(eval HCP_BUILD_DEPS_$N := $(strip $3))
$(eval $(N_lower)_DEPENDS := $(strip $4))
$(eval local_docker_xtra := $(strip $5))
$(eval local_bootstrap := $($(N_lower)_CMD_BOOTSTRAP))
$(eval local_configure := $($(N_lower)_CMD_CONFIGURE))
$(eval local_compile := $($(N_lower)_CMD_COMPILE))
$(eval local_install := $($(N_lower)_CMD_INSTALL))
$(if $($(N_lower)_BUILDER),,$(eval $(N_lower)_BUILDER := BUILDER))

$(eval $(call pp_add_layer,
	LAYER_$N,
	$($(N_lower)_BUILDER),
	BUILDER,
	$(call uniq,$(HCP_BUILD_DEPS_$N) $($(N_lower)_DEPENDS)),
	,
	$(HCP_BUILDER_SRC)/Makefile,
	,
	))

$(eval $(call pp_if_empty,local_bootstrap,/bin/true))
$(eval $(call pp_if_empty,local_configure,/bin/true))
$(eval $(call pp_if_empty,local_compile,/bin/true))
$(eval $(call pp_if_empty,local_install,/bin/true))

$(eval HCP_BUILD_PREFIX_$N := /destdir-$(N_lower))
$(eval HCP_BUILD_$N_OUT := $(HCP_BUILDER_OUT)/artifacts-$(N_lower))
$(eval HCP_BUILD_DEP_$N_BOOTSTRAPPED := $(HCP_BUILD_$N_OUT)/$(N_lower).bootstrapped)
$(eval HCP_BUILD_DEP_$N_CONFIGURED := $(HCP_BUILD_$N_OUT)/$(N_lower).configured)
$(eval HCP_BUILD_DEP_$N_COMPILED := $(HCP_BUILD_$N_OUT)/$(N_lower).compiled)

$(eval $(N_lower)_PKG_FORMAT := builder)
$(eval $(N_lower)_LOCAL_FILE := package_$(N_lower).tar.gz)
$(eval $(N_lower)_BUILT_PATH := $(HCP_BUILD_$N_OUT)/$($(N_lower)_LOCAL_FILE))
$(eval $(call cache_file_get,\
	$(N_lower),\
	$($(N_lower)_LOCAL_FILE),\
	builder/$(HCP_DEBIAN_NAME)))
$(eval $(call cache_file_update,\
	$(N_lower),\
	$($(N_lower)_LOCAL_FILE),\
	builder/$(HCP_DEBIAN_NAME),\
	$($(N_lower)_BUILT_PATH)))
$(if $($(N_lower)_LOCAL_PATH),,$(eval $(N_lower)_LOCAL_PATH := $(HCP_CACHE_$(N_lower)_FILE)))
$(if $($(N_lower)_LOCAL_PATH),,$(eval $(N_lower)_LOCAL_PATH := $($(N_lower)_BUILT_PATH)))

$(HCP_BUILD_$N_OUT): | $(HCP_BUILDER_OUT)
MDIRS += $(HCP_BUILD_$N_OUT)

ifneq (,$(LAZY))
$(eval HCP_BUILD_LAYER_DEP_$N := | $(HCP_LAYER_$N_TFILE))
else
$(eval HCP_BUILD_LAYER_DEP_$N := $(HCP_LAYER_$N_TFILE))
endif

$(eval local_docker_run := docker run --rm --init --label $(HCP_IMAGE_PREFIX)all=1 \
	--mount type=bind,source=$(HCP_BUILD_SRC_$N),destination=/builder-src \
	--mount type=bind,source=$(HCP_BUILD_$N_OUT),destination=/builder-output \
	--mount type=bind,source=$(HCP_SRC)/reffile,destination=/reffile,readonly \
	$(local_docker_xtra) $(HCP_LAYER_$N_DNAME) bash -c)
$(eval local_trap := /chowner.sh /reffile/reffile \
			/builder-src /builder-output)
$(eval local_run := trap '$(local_trap)' EXIT; cd /builder-src)

$(HCP_BUILD_DEP_$N_BOOTSTRAPPED): | $(HCP_BUILD_$N_OUT)
$(HCP_BUILD_DEP_$N_BOOTSTRAPPED): $(HCP_BUILD_LAYER_DEP_$N)
$(HCP_BUILD_DEP_$N_BOOTSTRAPPED):
	$Qecho "[Bootstrapping] $N"
	$Q$(local_docker_run) "$(local_run) && $(local_bootstrap)"
	$Qtouch $$@

$(HCP_BUILD_DEP_$N_CONFIGURED): $(HCP_BUILD_DEP_$N_BOOTSTRAPPED)
$(HCP_BUILD_DEP_$N_CONFIGURED):
	$Qecho "[Configuring] $N"
	$Q$(local_docker_run) "$(local_run) && $(local_configure)"
	$Qtouch $$@

$(HCP_BUILD_DEP_$N_COMPILED): $(HCP_BUILD_DEP_$N_CONFIGURED)
$(HCP_BUILD_DEP_$N_COMPILED):
	$Qecho "[Compiling] $N"
	$Q$(local_docker_run) "$(local_run) && $(local_compile)"
	$Qtouch $$@

$(eval local_install := export DESTDIR=/destdir && \
	$(local_install) && \
	tar zcf /builder-output/$($(N_lower)_LOCAL_FILE) -C /destdir .)
$($(N_lower)_BUILT_PATH): $(HCP_BUILD_DEP_$N_COMPILED)
$($(N_lower)_BUILT_PATH):
	$Qecho "[Packaging] $N"
	$Q$(local_docker_run) "$(local_run) && $(local_install)"

ifneq (,$(wildcard $(HCP_BUILD_$N_OUT)))
clean_$(N_lower):
	$Qrm -f $($(N_lower)_BUILT_PATH) \
		$(HCP_BUILD_DEP_$N_BOOTSTRAPPED) \
		$(HCP_BUILD_DEP_$N_CONFIGURED) \
		$(HCP_BUILD_DEP_$N_COMPILED)
	$Qrmdir $(HCP_BUILD_$N_OUT)
clean_layer_$(N_lower): clean_$(N_lower)
endif

endef

# The following function can provide a naive dependency rule that helps in many
# cases, especially for autotools-managed (autoconf/automake/libtool/etc)
# codebases which might be otherwise impossible to hook up to their
# auto-generated dependency scheme. It makes the output package file depend on
# the newest file in the source directory tree. This acts as a hair-trigger to
# re-run the install rule as soon as anything relevant could have conceivably
# changed. This approach does assume/require that the source's "install" rule
# will itself first trigger recompilation (or even reconfiguration, or even
# rebootstrapping) if the state of files demand it. This is fortunately true
# for autotools-managed code bases.
# $1 = package name, as passed as $1 to builder_add
define builder_simpledep
$(eval N_lower := $(strip $1))
$(eval N := $(shell echo "$(N_lower)" | tr '[:lower:]' '[:upper:]'))
$(eval LOCAL_SRCPATH := $(HCP_BUILD_SRC_$N))
$(eval LOCAL_nfile := $(shell find $(LOCAL_SRCPATH) -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -f2- -d" "))
$($(N_lower)_BUILT_PATH): $(LOCAL_nfile)
endef
