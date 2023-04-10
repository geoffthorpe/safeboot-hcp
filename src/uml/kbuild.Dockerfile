COPY kbuild.sh uml.kconfig myshutdown.c sd_notify_ready.c /
RUN chmod 766 /kbuild.sh
RUN chmod 644 /uml.kconfig /myshutdown.c /sd_notify_ready.c
