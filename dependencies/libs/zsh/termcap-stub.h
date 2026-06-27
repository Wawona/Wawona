#ifndef WWN_TERMCAP_STUB_H
#define WWN_TERMCAP_STUB_H

char *tgoto(const char *cap, int col, int row);
int tputs(const char *str, int affcnt, int (*outc)(int));
int tgetent(char *bp, const char *name);
char *tigetstr(const char *name);
int tigetflag(const char *name);
int tigetnum(const char *name);
char *tgetstr(const char *id, char **area);
int tgetnum(const char *id);
int tgetflag(const char *id);

#endif
