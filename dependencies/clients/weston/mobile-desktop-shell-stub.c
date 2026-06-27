/* In-process stub for weston-desktop-shell on tvOS/watchOS (fork/exec unavailable). */
#include <stddef.h>

int weston_desktop_shell_main(int argc, char **argv)
{
	(void)argc;
	(void)argv;
	return 0;
}
