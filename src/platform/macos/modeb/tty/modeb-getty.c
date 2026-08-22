/*
 * modeb-getty: Linux getty/login parity for Mode B text VTs.
 *
 * Runs as the PTY session leader under modeb-ttyd. Uses Doorman
 * (https://github.com/Wawona/doorman) for authenticate / acct_mgmt / setcred,
 * then drops privileges and execs the user's login shell on this same tty.
 *
 * We deliberately do NOT call doorman_open_session(): that path forks +
 * setsid(), which would detach from the Mode B PTY. Classic login(1) keeps
 * the controlling tty and execs in-process after auth.
 */

#include <errno.h>
#include <grp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

#include <doorman.h>

static char *read_line(const char *prompt, int echo) {
  if (prompt) {
    fputs(prompt, stdout);
    fflush(stdout);
  }

  struct termios oldt, newt;
  int is_tty = (tcgetattr(STDIN_FILENO, &oldt) == 0);
  if (is_tty && !echo) {
    newt = oldt;
    newt.c_lflag &= ~(tcflag_t)ECHO;
    tcsetattr(STDIN_FILENO, TCSANOW, &newt);
  }

  char *line = NULL;
  size_t cap = 0;
  ssize_t n = getline(&line, &cap, stdin);

  if (is_tty && !echo) {
    tcsetattr(STDIN_FILENO, TCSANOW, &oldt);
    fputc('\n', stdout);
    fflush(stdout);
  }

  if (n <= 0) {
    free(line);
    return NULL;
  }
  if (line[n - 1] == '\n')
    line[n - 1] = '\0';
  return line;
}

static int conversation(int num_msg, const doorman_message_t **msg,
                        doorman_response_t **resp, void *appdata) {
  (void)appdata;
  for (int i = 0; i < num_msg; i++) {
    switch (msg[i]->style) {
    case DOORMAN_PROMPT_ECHO_OFF:
      resp[i]->resp = read_line(msg[i]->msg, 0);
      if (!resp[i]->resp)
        return 1;
      break;
    case DOORMAN_PROMPT_ECHO_ON:
      resp[i]->resp = read_line(msg[i]->msg, 1);
      if (!resp[i]->resp)
        return 1;
      break;
    case DOORMAN_ERROR_MSG:
      fprintf(stderr, "%s\n", msg[i]->msg ? msg[i]->msg : "");
      break;
    case DOORMAN_TEXT_INFO:
      printf("%s\n", msg[i]->msg ? msg[i]->msg : "");
      fflush(stdout);
      break;
    }
  }
  return 0;
}

static int drop_and_exec_shell(const doorman_user_t *u) {
  if (!u || !u->name)
    return -1;

  const char *shell = (u->shell && u->shell[0]) ? u->shell : "/bin/zsh";
  const char *home = (u->home && u->home[0]) ? u->home : "/";

  if (seteuid(0) != 0 && geteuid() != 0) {
    fprintf(stderr, "modeb-getty: need root to open user session\n");
    return -1;
  }

  if (setgid(u->gid) != 0) {
    perror("setgid");
    return -1;
  }
  if (initgroups(u->name, (int)u->gid) != 0) {
    perror("initgroups");
    return -1;
  }
  if (setuid(u->uid) != 0) {
    perror("setuid");
    return -1;
  }
  if (u->uid != 0 && setuid(0) == 0) {
    fprintf(stderr, "modeb-getty: privilege drop failed\n");
    return -1;
  }

  if (chdir(home) != 0)
    (void)chdir("/");

  setenv("USER", u->name, 1);
  setenv("LOGNAME", u->name, 1);
  setenv("HOME", home, 1);
  setenv("SHELL", shell, 1);
  setenv("TERM", "linux", 1);
  setenv("COLORTERM", "truecolor", 1);
  setenv("WWN_MODEB_TTY", "1", 1);
  setenv("PATH",
         "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin", 1);
  setenv("XDG_SESSION_TYPE", "tty", 1);
  setenv("XDG_SESSION_DESKTOP", "modeb-console", 1);

  /* argv0 with leading '-' => login shell (Linux login(1) shape). */
  char dash_shell[256];
  const char *base = strrchr(shell, '/');
  base = base ? base + 1 : shell;
  snprintf(dash_shell, sizeof(dash_shell), "-%s", base);

  execl(shell, dash_shell, (char *)NULL);
  perror(shell);
  return -1;
}

static int try_login(void) {
  char host[256];
  if (gethostname(host, sizeof(host)) != 0)
    snprintf(host, sizeof(host), "wawona");
  host[sizeof(host) - 1] = '\0';

  printf("\n%s login: ", host);
  fflush(stdout);

  char *user = read_line(NULL, 1);
  if (!user || !user[0]) {
    free(user);
    sleep(1);
    return -1;
  }

  doorman_conv_t conv = {.conv = conversation, .appdata = NULL};
  doorman_handle_t *h = NULL;
  doorman_result_t r =
      doorman_start("login", user, &conv, DOORMAN_BACKEND_AUTO, &h);
  if (r != DOORMAN_SUCCESS) {
    fprintf(stderr, "Login incorrect\n");
    free(user);
    sleep(2);
    return -1;
  }

  (void)doorman_set_item(h, DOORMAN_ITEM_TTY, "modeb-vt");

  r = doorman_authenticate(h);
  if (r == DOORMAN_SUCCESS)
    r = doorman_acct_mgmt(h);
  if (r == DOORMAN_SUCCESS)
    r = doorman_setcred(h, DOORMAN_CRED_ESTABLISH);

  if (r != DOORMAN_SUCCESS) {
    fprintf(stderr, "Login incorrect\n");
    doorman_end(h);
    free(user);
    sleep(2);
    return -1;
  }

  doorman_user_t u;
  memset(&u, 0, sizeof(u));
  if (doorman_lookup_user(user, &u) != DOORMAN_SUCCESS) {
    fprintf(stderr, "Login incorrect\n");
    doorman_end(h);
    free(user);
    sleep(2);
    return -1;
  }

  printf("Welcome to Wawona Mode B console, %s.\n",
         u.full_name && u.full_name[0] ? u.full_name : user);
  fflush(stdout);

  /* End the auth handle before exec; credentials already established. */
  doorman_end(h);
  free(user);

  if (drop_and_exec_shell(&u) != 0) {
    doorman_free_user_fields(&u);
    sleep(2);
    return -1;
  }
  /* not reached */
  doorman_free_user_fields(&u);
  return -1;
}

int main(int argc, char **argv) {
  (void)argc;
  (void)argv;

  setenv("TERM", "linux", 1);
  setenv("COLORTERM", "truecolor", 1);
  setenv("WWN_MODEB_TTY", "1", 1);

  printf("\nWawona Mode B TTY (Doorman login / Linux getty parity)\n"
         "Ctrl+Option+F1-F6 switch VT | F7 kmscube | "
         "Ctrl+Option+Backspace Aqua\n");
  fflush(stdout);

  for (;;) {
    if (try_login() != 0)
      continue;
  }
  return 0;
}
