default: install

# We get asked to 'install' in a staging area, caller sets DESTDIR for this.
$(eval DESTDIR := $(strip $(DESTDIR)))
$(if $(DESTDIR),,$(error DESTDIR is not set))

# This would ultimately be /usr, or /usr/local. It must begin with "/"
LOCAL_PREFIX ?= /install-safeboot

# Put them both together and you get;
PREFIX ?= $(DESTDIR)$(LOCAL_PREFIX)
MDIRS += $(PREFIX)

# Build up the set of things to install
INSTALL_TGTS :=

INSTALL_TGTS += top
top_CHMOD := 644
top_SRCPATH := .
top_DESTPATH := .
top_FILES := functions.sh safeboot.conf

INSTALL_TGTS += sbin
sbin_CHMOD := 755
sbin_SRCPATH := sbin
sbin_DESTPATH := sbin
sbin_FILES := $(shell ls -1 sbin)
sbin_POST_CMD := (cd $(PREFIX)/sbin && rm -f attest_server.py && \
	ln -s attest-server attest_server.py)

INSTALL_TGTS += tests
tests_CHMOD := 755
tests_SRCPATH := tests
tests_DESTPATH := tests
tests_FILES := $(shell ls -1 tests)

# The target to install, trigger everything else from here
install: $(foreach x,$(INSTALL_TGTS),install_$x)

define install_tgt
$(eval x := $(strip $1))
$(eval cmd := /bin/true)
$(foreach f,$($x_FILES),
$(if $($x_PRE_CMD),$(eval cmd += && $($x_PRE_CMD)))
$(eval cmd += && install -D -T -m $($x_CHMOD) $($x_SRCPATH)/$f \
	$(PREFIX)/$($x_DESTPATH)/$f))
$(if $($x_POST_CMD),$(eval cmd += && $($x_POST_CMD)))
install_$x: | $(PREFIX)
	$Qecho "[Install] safeboot/$x"
	$Q$(cmd)
endef

$(foreach x,$(INSTALL_TGTS),$(eval $(call install_tgt,$x)))

$(MDIRS):
	$Qmkdir -p $@
