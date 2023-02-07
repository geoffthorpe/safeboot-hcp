# Minimal set of system tools that we want in all containers. E.g. because
# scripts require their presence (e.g. 'openssl', xxd, ...) or because they
# make the shell experience in the container tolerable (e.g. 'ip', 'ps',
# 'ping', ...)
RUN apt-get install -y openssl xxd procps iproute2 iputils-ping curl wget acl \
	lsof git jq procmail file time sudo dnsutils

# And some commonly-required middleware to minimize the amont of per-app
# package installation is required.
RUN apt-get install -y json-glib-tools libjson-perl libncurses5-dev \
	python3 python3-yaml python3-netifaces python3-psutil \
	python3-cryptography python3-openssl \
	python3-flask python3-requests uwsgi-plugin-python3

RUN mkdir -p /hcp/base
COPY chowner.sh /hcp/base/
RUN chmod 755 /hcp/base/chowner.sh
