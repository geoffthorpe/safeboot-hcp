RUN apt-get install -y ca-certificates
RUN mkdir -p /usr/share/ca-certificates/HCP/
COPY * /usr/share/ca-certificates/HCP/
RUN chmod 644 /usr/share/ca-certificates/HCP/*
RUN cd /usr/share/ca-certificates && \
  find HCP -type f >> /etc/ca-certificates.conf
RUN update-ca-certificates
