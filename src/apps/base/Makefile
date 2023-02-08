# HCP apps will all (for now) want;
# - the /hcp/common/ scripts (env, launcher, webapi, attester, purger, etc)
PKGS := hcp-common hcp-xtra hcp-tools
# - external packages, possibly locally-built
PKGS += swtpm-tools libtpms0
# - external packages, upstream, primarily for webapi endpoints
PKGS += json-glib-tools libjson-perl libncurses5-dev \
	python3 python3-yaml python3-netifaces python3-psutil \
	python3-cryptography python3-openssl \
	python3-flask python3-requests uwsgi-plugin-python3 \
	nginx uuid-runtime

$(eval $(call pp_add_layer,\
	APPS_BASE,\
	BASE,\
	APPS,\
	$(PKGS),\
	$(HCP_SRC)/apps/base/Dockerfile,\
	$(HCP_SRC)/apps/base/Makefile $(HCP_SRC)/apps/base/Dockerfile,\
	,\
	,\
	))
