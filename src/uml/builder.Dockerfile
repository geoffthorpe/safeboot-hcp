# TODO: revamp the pp_add_layer() API so we can add a parameter to pass
# build-args through docker-build. We already identify the kernel version
# and filename in the uml Makefile, so it should be passed in here;
COPY linux-6.1.9.tar.xz uml.kconfig myshutdown.c /
RUN cd / && \
	tar xJf linux-6.1.9.tar.xz && \
	rm linux-6.1.9.tar.xz && \
	cd linux-6.1.9 && \
	mv /uml.kconfig ./.config && \
	ARCH=um make oldconfig && \
	ARCH=um make -j10 && \
	ARCH=um make modules_install && \
	cp linux /linux && \
	strip /linux && \
	gcc -Wall -Werror -o /myshutdown /myshutdown.c && \
	rm /myshutdown.c && \
	strip /myshutdown
