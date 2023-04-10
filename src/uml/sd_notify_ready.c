#include <systemd/sd-daemon.h>

int main(int argc, char *argv[])
{
	sd_notify(0, "READY=1");
	return 0;
}
