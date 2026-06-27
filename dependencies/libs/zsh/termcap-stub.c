/* Minimal termcap/curses stubs for iOS cross-build. */
#include <stddef.h>

char *
tgoto(const char *cap, int col, int row)
{
	(void)col;
	(void)row;
	return (char *)cap;
}

int
tputs(const char *str, int affcnt, int (*outc)(int))
{
	(void)str;
	(void)affcnt;
	(void)outc;
	return 0;
}

int
tgetent(char *bp, const char *name)
{
	(void)bp;
	(void)name;
	return -1;
}

char *
tigetstr(const char *name)
{
	(void)name;
	return NULL;
}

int
tigetflag(const char *name)
{
	(void)name;
	return -1;
}

int
tigetnum(const char *name)
{
	(void)name;
	return -1;
}

char *
tgetstr(const char *id, char **area)
{
	(void)id;
	if (area)
		*area = NULL;
	return NULL;
}

int
tgetnum(const char *id)
{
	(void)id;
	return -1;
}

int
tgetflag(const char *id)
{
	(void)id;
	return -1;
}
