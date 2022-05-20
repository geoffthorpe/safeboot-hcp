RUN mkdir -p /hcp/swtpmsvc
COPY swtpmsvc/*.sh swtpmsvc/*.py /hcp/swtpmsvc/
RUN chmod 755 /hcp/swtpmsvc/*.sh /hcp/swtpmsvc/*.py
