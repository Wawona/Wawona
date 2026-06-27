#ifndef WWN_PTY_H
#define WWN_PTY_H

#include <sys/types.h>
#include <stddef.h>
#include <termios.h>

#ifdef __cplusplus
extern "C" {
#endif

#define WWN_PTY_API_VERSION 1

typedef struct wwn_pty_session wwn_pty_session;

int wwn_pty_open(int *master_fd, int *slave_fd, const struct winsize *ws);

int wwn_pty_is_allowed_shell_path(const char *shell_path);

pid_t wwn_pty_spawn_shell(const char *shell_path, char *const argv[],
                          int slave_fd, char *const envp[]);

pid_t wwn_pty_spawn_shell_paced(const char *shell_path, char *const argv[],
                                int slave_fd, int pace_read_fd,
                                char *const envp[]);

wwn_pty_session *wwn_pty_session_start(const char *shell_path,
                                       char *const argv[],
                                       char *const envp[],
                                       const struct winsize *ws);

ssize_t wwn_pty_read(int master_fd, void *buf, size_t len);
ssize_t wwn_pty_write(int master_fd, const void *buf, size_t len);

int wwn_pty_set_winsize(int master_fd, const struct winsize *ws);

int wwn_pty_reap(wwn_pty_session *session, int *exit_status);

void wwn_pty_session_destroy(wwn_pty_session *session);

#ifdef __cplusplus
}
#endif

#endif /* WWN_PTY_H */
