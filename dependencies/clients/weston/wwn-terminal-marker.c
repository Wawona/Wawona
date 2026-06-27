/*
 * WWNWaypipeRunner weak-links this to refuse launching weston-simple-shm when
 * the terminal archive is a compatibility shim. Real weston-terminal returns 0.
 */
int
wwn_weston_terminal_is_compat_shim(void)
{
	return 0;
}
