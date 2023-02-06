#include <sys/reboot.h>

/*
 * as my guide;
 *   http://svn.savannah.gnu.org/viewvc/sysvinit/sysvinit/tags/2.88dsf/src/reboot.h?view=markup
 */
#if defined(RB_POWER_OFF)
#  define MYMAGIC RB_POWER_OFF
#elif defined(RB_POWEROFF)
#  define MYMAGIC RB_POWEROFF
#else
#  define MYMAGIC BMAGIC_HALF
#endif

int main(int argc, char *argv[])
{
	reboot(MYMAGIC);
	/* NOTREACHED */
	return -1;
}
