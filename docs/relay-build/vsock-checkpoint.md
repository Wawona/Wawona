# Vsock / waypipe checkpoint

Status captured from measured mobile StaticCpu / guest probes.

## Proven

- Guest binds waypipe server on vsock port **1024**.
- Host receives real **16-byte** waypipe payloads (transport smoke).
- Console path prints `WAWONA_RELAY_READY=1` from session `postStart`
  after a short delay (readiness string, not authenticated frame proof).

## Not proven

- Authenticated readiness bound to the current machine/session.
- Import and display of a **real guest-rendered frame**.
- Disconnect / reconnect / reset with bounded host resource use.
- Host native waypipe client lifecycle matching the session.

## Next engineering steps

1. Host dials vsock 1024 only after matching machine id + generation.
2. Reject frames when session token / generation mismatches.
3. Decode one SHM/waypipe frame into the Machines surface and assert
   non-placeholder pixels.
4. Keep OCI-absent probes from counting as graphics acceptance.
