# Minimal set of system tools that we want in all containers. E.g. because
# scripts require their presence (e.g. 'openssl', xxd, ...) or because they
# make the shell experience in the container tolerable (e.g. 'ip', 'ps',
# 'ping', ...)
RUN apt-get install -y openssl xxd procps iproute2 iputils-ping curl wget acl \
	lsof git jq procmail file time sudo dnsutils

# And some commonly-required middleware to minimize the amont of per-app
# package installation is required.
RUN apt-get install -y json-glib-tools libjson-perl libncurses5-dev \
	python3 python3-yaml python3-distutils \
	python3-cryptography python3-openssl \
	python3-flask python3-requests uwsgi-plugin-python3

# If we are using upstream Debian packaging for "tpm2-tools" (and "tpm2-tss" by
# dependency), then this marker gets replaced by "apt-get install tpm2-tools",
# otherwise it gets stubbed out.  (In such cases, tpm2-tss/tpm2-tools will get
# built from source in the hcp/submodules layer, later on.)
HCP_BASE_3PLATFORM_TPM2_TOOLS

# Similar situation for Heimdal - it's either installed from package or built
# from source in a submodule.
HCP_BASE_3PLATFORM_HEIMDAL

# If xtra ("make yourself at home" stuff) packages are requested, this marker
# also gets replaced with an "apt-get install -y [...]" line, otherwise stubbed
# out.
HCP_BASE_3PLATFORM_XTRA

RUN mkdir -p /hcp/base
COPY chowner.sh /hcp/base/
RUN chmod 755 /hcp/base/chowner.sh
