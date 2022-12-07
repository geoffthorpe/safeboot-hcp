COPY deb_src_ify.sh /
RUN chmod 755 /deb_src_ify.sh && \
	/deb_src_ify.sh && \
	rm -f /deb_src_ify.sh && \
	apt-get update && \
	apt-get install -y build-essential devscripts dpkg-dev
RUN apt-get install -y \
    libx11-dev \
    git \
    libpulse-dev \
    meson
