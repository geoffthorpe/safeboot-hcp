# set version label
ARG BUILD_DATE
ARG VERSION
ARG GUACD_VERSION=1.1.0
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

# Copy build outputs
COPY --from=%%BUILDER_DNAME%% /tmp/out /tmp/out
COPY --from=%%BUILDER_DNAME%% /gclient /gclient

RUN \
  echo "**** install guacd ****" && \
  dpkg --path-include=/usr/share/doc/${PKG_NAME}/* \
    -i /tmp/out/guacd_${GUACD_VERSION}.deb && \
  echo "**** install packages ****" && \
  apt-get update && \
  apt-get install -y \
    gnupg && \
  curl -s https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add - && \
  echo 'deb https://deb.nodesource.com/node_16.x focal main' \
    > /etc/apt/sources.list.d/nodesource.list && \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install --no-install-recommends -y \
    ca-certificates \
    libfreerdp2-2 \
    libfreerdp-client2-2 \
    libossp-uuid16 \
    nodejs \
    obconf \
    openbox \
    python2 \
    xterm && \
  apt-get install -qy --no-install-recommends \
    $(cat /tmp/out/DEPENDENCIES) && \
  echo "**** grab websocat ****" && \
  WEBSOCAT_RELEASE=$(curl -sX GET "https://api.github.com/repos/vi/websocat/releases/latest" \
    | awk '/tag_name/{print $4;exit}' FS='[""]'); \
  curl -o \
    /usr/bin/websocat -fL \
    "https://github.com/vi/websocat/releases/download/${WEBSOCAT_RELEASE}/websocat.x86_64-unknown-linux-musl" && \
  chmod +x /usr/bin/websocat && \
  echo "**** openbox tweaks ****" && \
  sed -i \
    's/NLIMC/NLMC/g' \
    /etc/xdg/openbox/rc.xml

# add local files
COPY files.tar.gz /
RUN cd / && tar zxf files.tar.gz && rm files.tar.gz
