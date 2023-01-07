# If someone is running a caboodle container interactively, give their shell
# some helper functions. Also, trigger the resolution of where our config will
# be coming from by extracting something and ignoring it.
RUN echo "source /hcp/common/hcp.sh" >> /etc/bash.bashrc
RUN echo "hcp_config_extract_or '.' 'whatever' > /dev/null" >> /etc/bash.bashrc

# If we're not building WEBTOP, this step needs to fail/bypass silently
RUN test -L /chosen-wm && mv /chosen-wm /orig-chosen-wm && \
    ln -s /hcp/caboodle/custom-startwm.sh /chosen-wm || /bin/true
