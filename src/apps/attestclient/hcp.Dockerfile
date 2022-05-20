RUN mkdir -p /hcp/attestclient
COPY attestclient/*.sh /hcp/attestclient/
RUN chmod 755 /hcp/attestclient/*.sh
