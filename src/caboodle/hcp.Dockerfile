# If someone is running a caboodle container interactively, give their shell
# some helper functions and a greeting with the information we want them to
# have.
RUN echo "source /hcp/caboodle/common.sh" >> /etc/bash.bashrc

RUN mv /chosen-wm /orig-chosen-wm && \
    ln -s /hcp/caboodle/custom-startwm.sh /chosen-wm
