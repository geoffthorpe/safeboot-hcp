# If someone is running a monolith container interactively, give their shell
# some helper functions. Also, trigger the resolution of where our config will
# be coming from by extracting something and ignoring it.
RUN echo "source /hcp/common/hcp.sh" >> /etc/bash.bashrc
RUN echo "hcp_config_extract_or '.' 'whatever' > /dev/null" >> /etc/bash.bashrc
