RUN apt-get install -y xz-utils

ENV REL=jammy
ENV ARCH=amd64

# set version for s6 overlay
ARG S6_OVERLAY_VERSION="3.1.2.1"
ARG S6_OVERLAY_ARCH="x86_64"

# add s6 overlay and optional symlinks
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_OVERLAY_ARCH}.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-${S6_OVERLAY_ARCH}.tar.xz
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-symlinks-noarch.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-symlinks-noarch.tar.xz
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-symlinks-arch.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-symlinks-arch.tar.xz
RUN rm /tmp/s6-*.xz

ENV S6_CMD_WAIT_FOR_SERVICES_MAXTIME="0" \
    S6_VERBOSITY=1 \
    S6_STAGE2_HOOK=/docker-mods

RUN apt-get install -y \
    apt-transport-https \
    ca-certificates \
    dbus-x11 \
    gawk \
    gnupg2 \
    libfuse2 \
    libxfixes3 \
    libxml2 \
    libxrandr2 \
    netcat \
    openssh-client \
    pulseaudio \
    software-properties-common \
    sudo \
    x11-apps \
    x11-xserver-utils \
    xfonts-base \
    xorgxrdp \
    xrdp \
    xserver-xorg-core \
    xserver-xorg-video-intel \
    xserver-xorg-video-amdgpu \
    xserver-xorg-video-ati \
    xutils \
    zlib1g
RUN useradd -u 911 -U -d /config -s /bin/false abc && \
  usermod -G users abc && \
  mkdir -p \
    /app \
    /config \
    /defaults && \
  echo "abc:abc" | chpasswd && \
  usermod -aG sudo abc
# Subsequent stuff (like installing firefox) depends on this;
COPY deb_contrib_nonfree_ify.sh /
RUN chmod 755 /deb_contrib_nonfree_ify.sh && \
	/deb_contrib_nonfree_ify.sh && \
	rm -f /deb_contrib_nonfree_ify.sh && \
	apt-get update
COPY files.tar.gz /
RUN cd / && tar zxf files.tar.gz && rm files.tar.gz
