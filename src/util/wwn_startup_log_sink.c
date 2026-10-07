/* Startup log sink pointer. Defined in C so Swift and Rust can share it.
 * Replaces the definition that lived in WWNStartupLogger.m. */

void (*wwn_startup_log_sink)(const char *module, const char *msg) = 0;
int wwn_log_quiet = 0;
