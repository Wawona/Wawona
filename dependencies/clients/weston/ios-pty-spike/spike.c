/*
 * Phase 0 harness: PTY open + bundled-zsh spawn smoke test for iOS sandbox.
 * Run on device/simulator with WAWONA_ROOTFS and WAWONA_SHELL set.
 */
#include "wwn_pty.h"

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern char **environ;

static void
report(const char *label, int ok)
{
	printf("[%s] %s\n", label, ok ? "PASS" : "FAIL");
}

int
main(int argc, char *argv[])
{
	const char *shell;
	char *const spawn_argv[] = { NULL, NULL };
	int master = -1, slave = -1;
	char buf[512];
	ssize_t n;
	pid_t pid;
	int path_ok;

	(void)argc;
	(void)argv;

	shell = getenv("WAWONA_SHELL");
	if (!shell || !shell[0])
		shell = getenv("SHELL");
	if (!shell || !shell[0]) {
		const char *root = getenv("WAWONA_ROOTFS");
		if (root && root[0]) {
			static char fallback[512];
			snprintf(fallback, sizeof fallback, "%s/usr/bin/zsh", root);
			shell = fallback;
		}
	}
	if (!shell || !shell[0]) {
		fprintf(stderr, "Set WAWONA_SHELL or WAWONA_ROOTFS before running spike\n");
		return 2;
	}

	printf("wawona-pty-spike: shell=%s\n", shell);
	printf("WAWONA_ROOTFS=%s\n", getenv("WAWONA_ROOTFS") ?: "(unset)");
	printf("WAWONA_BUNDLE_ROOTFS=%s\n", getenv("WAWONA_BUNDLE_ROOTFS") ?: "(unset)");

	path_ok = wwn_pty_is_allowed_shell_path(shell);
	report("path_policy", path_ok);
	if (!path_ok) {
		fprintf(stderr, "shell path rejected by wwn_pty policy (errno=%d)\n", errno);
		return 1;
	}

	if (wwn_pty_open(&master, &slave, NULL) != 0) {
		fprintf(stderr, "wwn_pty_open failed: %s\n", strerror(errno));
		report("posix_openpt", 0);
		return 1;
	}
	report("posix_openpt", 1);
	report("grantpt", 1);
	report("unlockpt", 1);

	spawn_argv[0] = (char *)shell;
	pid = wwn_pty_spawn_shell(shell, spawn_argv, slave, environ);
	close(slave);
	if (pid < 0) {
		fprintf(stderr, "wwn_pty_spawn_shell failed: %s\n", strerror(errno));
		report("posix_spawn", 0);
		close(master);
		return 1;
	}
	report("posix_spawn", 1);
	printf("spawn pid=%d\n", (int)pid);

	if (wwn_pty_write(master, "echo hello\n", 11) < 0) {
		fprintf(stderr, "write failed: %s\n", strerror(errno));
		report("master_write", 0);
		close(master);
		return 1;
	}
	report("master_write", 1);

	memset(buf, 0, sizeof buf);
	n = wwn_pty_read(master, buf, sizeof buf - 1);
	if (n < 0) {
		fprintf(stderr, "read failed: %s\n", strerror(errno));
		report("master_read", 0);
		close(master);
		return 1;
	}
	report("master_read", 1);
	printf("read %zd bytes: %.*s\n", n, (int)n, buf);
	report("echo_hello", strstr(buf, "hello") != NULL);

	close(master);
	kill(pid, SIGHUP);
	return 0;
}
