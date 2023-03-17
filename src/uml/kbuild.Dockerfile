COPY kbuild.sh uml.kconfig myshutdown.c /
RUN chmod 766 /kbuild.sh
RUN chmod 644 /uml.kconfig /myshutdown.c
