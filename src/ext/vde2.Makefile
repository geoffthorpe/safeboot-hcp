define vde2_patch
$(eval N_lower := $(strip $1))
$(eval N_upper := $(strip $2))
$(eval p := $(HCP_SRC)/ext/vde2_$(N_lower)_patch.diff)
$(eval d := $(HCP_$(N_upper)_SRC))
$(if $(wildcard $d/.hcp-patched),,
$(info Applying patch to '$(N_lower)')
$(shell cd $d && patch -p1 < $p >/dev/null 2>&1 && touch .hcp-patched))
endef


HCP_S2ARGV_EXECS_SRC := $(TOP)/ext-vde/s2argv-execs
HCP_S2ARGV_EXECS_PREFIX := /usr
s2argv-execs_CMD_BOOTSTRAP := mkdir -p build
s2argv-execs_CMD_CONFIGURE := cd build && cmake -DCMAKE_INSTALL_PREFIX:PATH=$(HCP_S2ARGV_EXECS_PREFIX) ..
s2argv-execs_CMD_COMPILE := cd build && make $(HCP_BUILDER_MAKE_PARALLEL)
s2argv-execs_CMD_INSTALL := cd build && make $(HCP_BUILDER_MAKE_PARALLEL) install
$(eval $(call builder_add,\
	s2argv-execs,\
	$(HCP_S2ARGV_EXECS_SRC),\
	,\
	,\
	))
$(eval $(call builder_simpledep,s2argv-execs))
$(eval $(call vde2_patch,s2argv-execs,S2ARGV_EXECS))

HCP_VDEPLUG4_SRC := $(TOP)/ext-vde/vdeplug4
HCP_VDEPLUG4_PREFIX := /usr
vdeplug4_CMD_BOOTSTRAP := mkdir -p build
vdeplug4_CMD_CONFIGURE := cd build && cmake -DCMAKE_INSTALL_PREFIX:PATH=$(HCP_VDEPLUG4_PREFIX) ..
vdeplug4_CMD_COMPILE := cd build && make $(HCP_BUILDER_MAKE_PARALLEL)
vdeplug4_CMD_INSTALL := cd build && make $(HCP_BUILDER_MAKE_PARALLEL) install
$(eval $(call builder_add,\
	vdeplug4,\
	$(HCP_VDEPLUG4_SRC),\
	s2argv-execs,\
	s2argv-execs,\
	))
$(eval $(call builder_simpledep,vdeplug4))

HCP_LIBSLIRP_SRC := $(TOP)/ext-vde/libslirp
HCP_LIBSLIRP_PREFIX := /usr
libslirp_CMD_COMPILE := meson build
libslirp_CMD_INSTALL := ninja -C build install
$(eval $(call builder_add,\
	libslirp,\
	$(HCP_LIBSLIRP_SRC),\
	,\
	,\
	))
$(eval $(call builder_simpledep,libslirp))

HCP_LIBVDESLIRP_SRC := $(TOP)/ext-vde/libvdeslirp
HCP_LIBVDESLIRP_PREFIX := /usr
libvdeslirp_CMD_BOOTSTRAP := mkdir -p build
libvdeslirp_CMD_CONFIGURE := cd build && cmake -DCMAKE_INSTALL_PREFIX:PATH=$(HCP_LIBVDESLIRP_PREFIX) ..
libvdeslirp_CMD_COMPILE := cd build && make $(HCP_BUILDER_MAKE_PARALLEL)
libvdeslirp_CMD_INSTALL := cd build && make $(HCP_BUILDER_MAKE_PARALLEL) install
$(eval $(call builder_add,\
	libvdeslirp,\
	$(HCP_LIBVDESLIRP_SRC),\
	libslirp vdeplug4,\
	libslirp vdeplug4,\
	))
$(eval $(call builder_simpledep,libvdeslirp))
$(eval $(call vde2_patch,libvdeslirp,LIBVDESLIRP))

HCP_VDEPLUG_SLIRP_SRC := $(TOP)/ext-vde/vdeplug_slirp
HCP_VDEPLUG_SLIRP_PREFIX := /usr
vdeplug_slirp_CMD_BOOTSTRAP := mkdir -p build
vdeplug_slirp_CMD_CONFIGURE := cd build && cmake -DCMAKE_INSTALL_PREFIX:PATH=$(HCP_VDEPLUG_SLIRP_PREFIX) ..
vdeplug_slirp_CMD_COMPILE := cd build && make $(HCP_BUILDER_MAKE_PARALLEL)
vdeplug_slirp_CMD_INSTALL := cd build && make $(HCP_BUILDER_MAKE_PARALLEL) install
$(eval $(call builder_add,\
	vdeplug_slirp,\
	$(HCP_VDEPLUG_SLIRP_SRC),\
	libvdeslirp,\
	libvdeslirp,\
	))
$(eval $(call builder_simpledep,vdeplug_slirp))

HCP_VDE2_SRC := $(TOP)/ext-vde/vde-2
HCP_VDE2_PREFIX := /usr/legacy
vde2_CMD_BOOTSTRAP := autoreconf --install
vde2_CMD_CONFIGURE := ./configure --prefix=$(HCP_VDE2_PREFIX)
vde2_CMD_COMPILE := make $(HCP_BUILDER_MAKE_PARALLEL)
vde2_CMD_INSTALL := make $(HCP_BUILDER_MAKE_PARALLEL) install
$(eval $(call builder_add,\
	vde2,\
	$(HCP_VDE2_SRC),\
	,\
	,\
	))
$(eval $(call builder_simpledep,vde2))
