import Base
import ./job.bend as Job

# Retrying Stop must not change its result.
law stop_idempotent:
  for phase: Job.Phase
  {Job.stop(Job.stop(phase)) == Job.stop(phase) : Job.Phase}

law leaves_idle:
  {Job.stop(Job.Idle{}) == Job.Idle{} : Job.Phase}

law ends_running:
  {Job.stop(Job.Running{}) == Job.Stopped{} : Job.Phase}

law keeps_stopped:
  {Job.stop(Job.Stopped{}) == Job.Stopped{} : Job.Phase}

# Start always reaches Running, and a second Start stays there.
law start_is_running:
  for phase: Job.Phase
  {Job.start(phase) == Job.Running{} : Job.Phase}

law start_idempotent:
  for phase: Job.Phase
  {Job.start(Job.start(phase)) == Job.start(phase) : Job.Phase}

law stop_after_start:
  for phase: Job.Phase
  {Job.stop(Job.start(phase)) == Job.Stopped{} : Job.Phase}

law start_after_stop:
  for phase: Job.Phase
  {Job.start(Job.stop(phase)) == Job.Running{} : Job.Phase}

# After two backs, a third changes nothing. Section -> Settings -> Machines.
# Settings is a cover, so one back from Section is not yet a fixed point.
law back_idempotent:
  for place: Job.Place
  {Job.back(Job.back(Job.back(place))) == Job.back(Job.back(place)) : Job.Place}

law open_machine_back:
  for place: Job.Place
  {Job.back(Job.open_machine(place)) == Job.Machines{} : Job.Place}

law open_section_back:
  for place: Job.Place
  {Job.back(Job.open_section(place)) == Job.Settings{} : Job.Place}

law select_machines_root:
  for place: Job.Place
  {Job.select_machines(place) == Job.Machines{} : Job.Place}

law select_settings_root:
  for place: Job.Place
  {Job.select_settings(place) == Job.Settings{} : Job.Place}

# Catalog root stays. Settings cover backs to Machines.
law select_stays:
  for place: Job.Place
  {Job.back(Job.select_machines(place)) == Job.select_machines(place) : Job.Place}

law settings_backs_to_machines:
  {Job.back(Job.Settings{}) == Job.Machines{} : Job.Place}

law select_settings_then_back:
  for place: Job.Place
  {Job.back(Job.select_settings(place)) == Job.Machines{} : Job.Place}

# Non-negative axis of clamp_rect. Origin and origin+span stay inside the limit.
law origin_le_limit:
  for +x: Nat
  for +limit: Nat
  {Nat.is_le(Job.clamp_origin(x, limit), limit) == True{} : Bool}

law right_le_limit:
  for +limit: Nat
  for +x: Nat
  for +span: Nat
  {Nat.is_le(Job.clamp_right(x, span, limit), limit) == True{} : Bool}

law clamp_inside_example:
  {Job.clamp_right(8n, 4n, 10n) == 10n : Nat}

law clamp_inset_example:
  {Job.clamp_right(2n, 2n, 10n) == 4n : Nat}

# normalize_ssh_port. In 1..=65535 the number is kept. Otherwise the fallback.
law port_keeps_22:
  {Job.normalize(22n, 1n) == 22n : Nat}

law port_rejects_zero:
  {Job.normalize(0n, 22n) == 22n : Nat}

law port_rejects_high:
  {Job.normalize(65536n, 22n) == 22n : Nat}

law port_keeps_max:
  {Job.normalize(65535n, 1n) == 65535n : Nat}

law port_fallback_when_out:
  for +raw: Nat
  for +fallback: Nat
  {Bool.or(Job.in_port(raw), Nat.is_eq(Job.normalize(raw, fallback), fallback)) == True{} : Bool}

# One-thread generation step.
law bump_steps:
  for n: Nat
  {Job.bump(n) == 1n+n : Nat}

law gamma_zero:
  {Job.gamma_bytes(0n) == 0n : Nat}

law gamma_step:
  for n: Nat
  {Job.gamma_bytes(1n+n) == Nat.add(6n, Job.gamma_bytes(n)) : Nat}

law scale_zero:
  {Job.scale_units(0n) == 120n : Nat}

law scale_at_least_120:
  for +centi: Nat
  {Nat.is_ge(Job.scale_units(centi), 120n) == True{} : Bool}

law idle_keeps:
  for n: Nat
  {Job.idle_remove(n, False{}) == n : Nat}

law idle_drops:
  for n: Nat
  {Job.idle_remove(1n+n, True{}) == n : Nat}

law idle_zero:
  {Job.idle_remove(0n, True{}) == 0n : Nat}

law hold_now:
  for n: Nat
  {Job.hold_required(n, n) == False{} : Bool}

law hold_later:
  for n: Nat
  {Job.hold_required(1n+n, n) == True{} : Bool}

law rejects_second_is_flag:
  for already: Bool
  {Job.rejects_second(already) == already : Bool}

law oneshot_is_not_both:
  for defunct: Bool
  for active: Bool
  {Job.oneshot_allows(defunct, active) == Bool.not(Bool.and(defunct, active)) : Bool}

law fifo_is_armed_unpresented:
  for armed: Bool
  for presented: Bool
  {Job.fifo_blocks(armed, presented) == Bool.and(armed, Bool.not(presented)) : Bool}

law bit_zero:
  {Job.bit_ok(0n) == True{} : Bool}

law bit_one:
  {Job.bit_ok(1n) == True{} : Bool}

law bit_rest:
  for n: Nat
  {Job.bit_ok(1n+1n+n) == False{} : Bool}

law alpha_zero:
  {Job.alpha_ok(0n) == True{} : Bool}

law alpha_one:
  {Job.alpha_ok(1n) == True{} : Bool}

law alpha_low:
  {Job.alpha_ok(2n) == True{} : Bool}

law alpha_rest:
  for n: Nat
  {Job.alpha_ok(1n+1n+1n+n) == False{} : Bool}

law content_known:
  {Job.content_ok(Job.HintNone{}) == True{} : Bool}

law content_photo:
  {Job.content_ok(Job.Photo{}) == True{} : Bool}

law content_video:
  {Job.content_ok(Job.Video{}) == True{} : Bool}

law content_game:
  {Job.content_ok(Job.Game{}) == True{} : Bool}

law content_other:
  {Job.content_ok(Job.Other{}) == False{} : Bool}

law cursor_zero:
  {Job.cursor_ok(0n) == False{} : Bool}

law cursor_pos:
  for n: Nat
  {Job.cursor_ok(1n+n) == True{} : Bool}

law pixel_one:
  {Job.one_by_one(1n, 1n) == True{} : Bool}

law pixel_wide:
  for n: Nat
  {Job.one_by_one(1n+1n+n, 1n) == False{} : Bool}

law size_pos:
  for w: Nat
  for h: Nat
  {Job.size_positive(1n+w, 1n+h) == True{} : Bool}

law dest_unset:
  {Job.dest_valid(True{}, 0n, 0n) == True{} : Bool}

law dest_empty:
  {Job.dest_valid(False{}, 0n, 0n) == False{} : Bool}

# Closing a window removes it from the keyboard-eligible set.
# Selecting an id that is not eligible stays unset.

law select_missing_empty:
  for id: Nat
  {Job.select(Job.Empty{}, id) == Job.Unset{} : Job.Focus}

law select_present:
  {Job.select(Job.Link{ 1n, Job.Empty{} }, 1n) == Job.On{ 1n } : Job.Focus}

law select_other:
  {Job.select(Job.Link{ 1n, Job.Empty{} }, 2n) == Job.Unset{} : Job.Focus}

law close_drops_empty:
  for id: Nat
  {Job.in(Job.without(Job.Empty{}, id), id) == False{} : Bool}

law close_drops_one:
  {Job.in(Job.without(Job.Link{ 1n, Job.Empty{} }, 1n), 1n) == False{} : Bool}

law close_keeps_neighbor:
  {Job.in(Job.without(Job.Link{ 1n, Job.Link{ 2n, Job.Empty{} } }, 1n), 2n) == True{} : Bool}

law select_closed_one:
  {Job.select(Job.without(Job.Link{ 1n, Job.Empty{} }, 1n), 1n) == Job.Unset{} : Job.Focus}

law select_after_close_empty:
  for id: Nat
  {Job.select(Job.without(Job.Empty{}, id), id) == Job.Unset{} : Job.Focus}

law close_clears:
  for id: Nat
  {Job.clear(Job.On{ id }, id) == Job.Unset{} : Job.Focus}

law close_keeps_other:
  {Job.clear(Job.On{ 1n }, 0n) == Job.On{ 1n } : Job.Focus}

# Exact UI transitions. The same laws apply on every ALL_TARGETS host.

law store_is:
  for b: Bool
  {Job.store(b) == b : Bool}

law flip_back:
  for b: Bool
  {Job.flip(Job.flip(b)) == b : Bool}

law remote_needs_waypipe:
  for on: Bool
  {Job.remote_on(False{}, on) == False{} : Bool}

law remote_follows:
  for on: Bool
  {Job.remote_on(True{}, on) == on : Bool}

law save_rejects_blank:
  {Job.save_when(False{}) == False{} : Bool}

law save_keeps_named:
  {Job.save_when(True{}) == True{} : Bool}

law section_hidden:
  {Job.open_when(False{}) == False{} : Bool}

law section_shown:
  {Job.open_when(True{}) == True{} : Bool}

law factor_zero:
  {Job.factor_ok(0n) == True{} : Bool}

law factor_rest:
  for n: Nat
  {Job.factor_ok(1n+n) == True{} : Bool}

law lease_zero:
  {Job.lease_empty(0n) == True{} : Bool}

law lease_some:
  for n: Nat
  {Job.lease_empty(1n+n) == False{} : Bool}

law absent_yes:
  {Job.absent(False{}) == True{} : Bool}

law absent_no:
  {Job.absent(True{}) == False{} : Bool}

law frac_dest_ok:
  for aligned: Bool
  {Job.frac_reject(True{}, aligned) == False{} : Bool}

law frac_aligned:
  {Job.frac_reject(False{}, True{}) == False{} : Bool}

law frac_misaligned:
  {Job.frac_reject(False{}, False{}) == True{} : Bool}
