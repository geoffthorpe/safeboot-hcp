RUN apt-get install -y gcc g++ make \
	automake autoconf autoconf-archive libtool pkg-config \
	expect gawk socat help2man bison flex \
	libc-dev libssl-dev libseccomp-dev libtasn1-6-dev \
	libjson-c-dev libcurl4-openssl-dev libqrencode-dev \
	uuid-dev gnu-efi binutils-dev libjson-glib-dev \
	libfile-slurp-perl libncurses5-dev comerr-dev libdb-dev
COPY deb_src_ify.sh /
RUN chmod 755 /deb_src_ify.sh && /deb_src_ify.sh && rm -f /deb_src_ify.sh && \
	apt-get update && \
	apt-get install -y build-essential devscripts dpkg-dev
