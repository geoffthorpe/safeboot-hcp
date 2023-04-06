# The hostfs entry in fstab seems to load the '9p' module automatically but not
# the virtio transport that it depends on. Strangely, a second attempt to do
# the mount seems to work. Anyway, this forces things;
RUN echo "9p" > /etc/modules-load.d/hcp.conf
RUN echo "9pnet_virtio" >> /etc/modules-load.d/hcp.conf

# Set up fstab. Note, recent kernels cap the msize at 512KB, even though docs
# still seem to suggest you can (and might want to) set it way higher. Here we
# try for 10MB, but in practice it seems to get pinned at 512KB.
RUN echo "/dev/sda1 / ext4 defaults 0 1" > /etc/fstab
RUN echo "hcphostfs /hostfs 9p trans=virtio,msize=10485760 0 0" >> /etc/fstab

# Inhibit painfully-slow boot detection of resume
RUN echo "RESUME=none" > /etc/initramfs-tools/conf.d/resume
RUN update-initramfs -u

# Coax systemd into;
# - handling resolv.conf setup from DHCP (systemd-resolved),
# - naming our VDE interface 'vde0' (10-vde.link),
# - using DHCP (25-vde.network).
RUN systemctl enable systemd-resolved
COPY 10-vde.link 25-vde.network /etc/systemd/network/
RUN chmod 644 /etc/systemd/network/10-vde.link /etc/systemd/network/25-vde.network
RUN systemctl enable systemd-networkd

# Add the script that mounts, loads, and executes the workload passed in from
# the runner container (the one creating the VM we're running in).
COPY qemu_init.py /
RUN chmod 755 /qemu_init.py

# Add a systemd unit to start that qemu_init.py script when the OS is ready.
COPY hcp_systemd.service /etc/systemd/system/
RUN chmod 644 /etc/systemd/system/hcp_systemd.service
RUN systemctl enable hcp_systemd.service

RUN echo "root:123456" | chpasswd
