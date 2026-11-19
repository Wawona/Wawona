import Base
import ./job.bend as Job
import ./LAWS.bend as Laws

def Laws.stop_idempotent(phase):
  match phase:
    case Job.Idle{}: {==}
    case Job.Running{}: {==}
    case Job.Stopped{}: {==}

def Laws.leaves_idle():
  {==}

def Laws.ends_running():
  {==}

def Laws.keeps_stopped():
  {==}

def Laws.start_is_running(phase):
  match phase:
    case Job.Idle{}: {==}
    case Job.Running{}: {==}
    case Job.Stopped{}: {==}

def Laws.start_idempotent(phase):
  match phase:
    case Job.Idle{}: {==}
    case Job.Running{}: {==}
    case Job.Stopped{}: {==}

def Laws.stop_after_start(phase):
  match phase:
    case Job.Idle{}: {==}
    case Job.Running{}: {==}
    case Job.Stopped{}: {==}

def Laws.start_after_stop(phase):
  match phase:
    case Job.Idle{}: {==}
    case Job.Running{}: {==}
    case Job.Stopped{}: {==}

def Laws.back_idempotent(place):
  match place:
    case Job.Machines{}: {==}
    case Job.Machine{}: {==}
    case Job.Session{}: {==}
    case Job.Add{}: {==}
    case Job.CreateTag{}: {==}
    case Job.Tabs{}: {==}
    case Job.Settings{}: {==}
    case Job.Section{}: {==}

def Laws.open_machine_back(place):
  match place:
    case Job.Machines{}: {==}
    case Job.Machine{}: {==}
    case Job.Session{}: {==}
    case Job.Add{}: {==}
    case Job.CreateTag{}: {==}
    case Job.Tabs{}: {==}
    case Job.Settings{}: {==}
    case Job.Section{}: {==}

def Laws.open_section_back(place):
  match place:
    case Job.Machines{}: {==}
    case Job.Machine{}: {==}
    case Job.Session{}: {==}
    case Job.Add{}: {==}
    case Job.CreateTag{}: {==}
    case Job.Tabs{}: {==}
    case Job.Settings{}: {==}
    case Job.Section{}: {==}

def Laws.select_machines_root(place):
  match place:
    case Job.Machines{}: {==}
    case Job.Machine{}: {==}
    case Job.Session{}: {==}
    case Job.Add{}: {==}
    case Job.CreateTag{}: {==}
    case Job.Tabs{}: {==}
    case Job.Settings{}: {==}
    case Job.Section{}: {==}

def Laws.select_settings_root(place):
  match place:
    case Job.Machines{}: {==}
    case Job.Machine{}: {==}
    case Job.Session{}: {==}
    case Job.Add{}: {==}
    case Job.CreateTag{}: {==}
    case Job.Tabs{}: {==}
    case Job.Settings{}: {==}
    case Job.Section{}: {==}

def Laws.select_stays(place):
  match place:
    case Job.Machines{}: {==}
    case Job.Machine{}: {==}
    case Job.Session{}: {==}
    case Job.Add{}: {==}
    case Job.CreateTag{}: {==}
    case Job.Tabs{}: {==}
    case Job.Settings{}: {==}
    case Job.Section{}: {==}

def Laws.settings_backs_to_machines():
  {==}

def Laws.select_settings_then_back(place):
  match place:
    case Job.Machines{}: {==}
    case Job.Machine{}: {==}
    case Job.Session{}: {==}
    case Job.Add{}: {==}
    case Job.CreateTag{}: {==}
    case Job.Tabs{}: {==}
    case Job.Settings{}: {==}
    case Job.Section{}: {==}

def le_zero(n: Nat) -> {Nat.is_le(0n, n) == True{} : Bool}:
  match n:
    case 0n:
      {==}
    case 1n+p:
      {==}

def Laws.origin_le_limit(x, limit):
  match x limit:
    case 0n n:
      le_zero(n)
    case 1n+xp 0n:
      {==}
    case 1n+xp 1n+lp:
      Laws.origin_le_limit(xp, lp)

def Laws.right_le_limit(limit, x, span):
  match limit:
    case 0n:
      match x:
        case 0n:
          {==}
        case 1n+xp:
          {==}
    case 1n+lp:
      match x:
        case 0n:
          match span:
            case 0n:
              {==}
            case 1n+sp:
              Laws.right_le_limit(lp, 0n, sp)
        case 1n+xp:
          Laws.right_le_limit(lp, xp, span)

def Laws.clamp_inside_example():
  {==}

def Laws.clamp_inset_example():
  {==}

def Laws.port_keeps_22():
  {==}

def Laws.port_rejects_zero():
  {==}

def Laws.port_rejects_high():
  {==}

def Laws.port_keeps_max():
  {==}

def eq_refl(n: Nat) -> {Nat.is_eq(n, n) == True{} : Bool}:
  match n:
    case 0n:
      {==}
    case 1n+p:
      eq_refl(p)

def port_fallback_go(flag: Bool, +raw: Nat, +fallback: Nat) -> {Bool.or(flag, Nat.is_eq(Job.normalize_port(flag, raw, fallback), fallback)) == True{} : Bool}:
  match flag:
    case True{}:
      {==}
    case False{}:
      eq_refl(fallback)

def Laws.port_fallback_when_out(raw, fallback):
  port_fallback_go(Job.in_port(raw), raw, fallback)

def Laws.bump_steps(n):
  {==}

def Laws.gamma_zero():
  {==}

def Laws.gamma_step(n):
  {==}

def Laws.scale_zero():
  {==}

def Laws.scale_at_least_120(centi):
  Nat.max_ge_l(120n, Job.quot(Nat.divmod(Nat.mul(centi, 120n), 100n)))

def Laws.idle_keeps(n):
  {==}

def Laws.idle_drops(n):
  match n:
    case 0n:
      {==}
    case 1n+p:
      {==}

def Laws.idle_zero():
  {==}

def Laws.hold_now(n):
  match n:
    case 0n:
      {==}
    case 1n+p:
      Laws.hold_now(p)

def Laws.hold_later(n):
  match n:
    case 0n:
      {==}
    case 1n+p:
      Laws.hold_later(p)

def Laws.rejects_second_is_flag(already):
  match already:
    case False{}:
      {==}
    case True{}:
      {==}

def Laws.oneshot_is_not_both(defunct, active):
  match defunct active:
    case False{} False{}: {==}
    case False{} True{}: {==}
    case True{} False{}: {==}
    case True{} True{}: {==}

def Laws.fifo_is_armed_unpresented(armed, presented):
  match armed presented:
    case False{} False{}: {==}
    case False{} True{}: {==}
    case True{} False{}: {==}
    case True{} True{}: {==}

def Laws.bit_zero():
  {==}

def Laws.bit_one():
  {==}

def Laws.bit_rest(n):
  {==}

def Laws.alpha_zero():
  {==}

def Laws.alpha_one():
  {==}

def Laws.alpha_low():
  {==}

def Laws.alpha_rest(n):
  {==}

def Laws.content_known():
  {==}

def Laws.content_photo():
  {==}

def Laws.content_video():
  {==}

def Laws.content_game():
  {==}

def Laws.content_other():
  {==}

def Laws.cursor_zero():
  {==}

def Laws.cursor_pos(n):
  {==}

def Laws.pixel_one():
  {==}

def Laws.pixel_wide(n):
  {==}

def Laws.size_pos(w, h):
  {==}

def Laws.dest_unset():
  {==}

def Laws.dest_empty():
  {==}

def Laws.select_missing_empty(id):
  {==}

def Laws.select_present():
  {==}

def Laws.select_other():
  {==}

def Laws.close_drops_empty(id):
  {==}

def Laws.close_drops_one():
  {==}

def Laws.close_keeps_neighbor():
  {==}

def Laws.select_closed_one():
  {==}

def Laws.select_after_close_empty(id):
  {==}

def clears_from(p: Nat, cur: Nat) -> {Job.clear_go(p, p, cur) == Job.Unset{} : Job.Focus}:
  match p:
    case 0n:
      {==}
    case 1n+q:
      clears_from(q, cur)

def Laws.close_clears(id):
  +i = id
  clears_from(i, i)

def Laws.close_keeps_other():
  {==}

def Laws.store_is(b):
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

def Laws.flip_back(b):
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

def Laws.remote_needs_waypipe(on):
  match on:
    case True{}:
      {==}
    case False{}:
      {==}

def Laws.remote_follows(on):
  match on:
    case True{}:
      {==}
    case False{}:
      {==}

def Laws.save_rejects_blank():
  {==}

def Laws.save_keeps_named():
  {==}

def Laws.section_hidden():
  {==}

def Laws.section_shown():
  {==}

def Laws.factor_zero():
  {==}

def Laws.factor_rest(n):
  {==}

def Laws.lease_zero():
  {==}

def Laws.lease_some(n):
  {==}

def Laws.absent_yes():
  {==}

def Laws.absent_no():
  {==}

def Laws.frac_dest_ok(aligned):
  match aligned:
    case True{}:
      {==}
    case False{}:
      {==}

def Laws.frac_aligned():
  {==}

def Laws.frac_misaligned():
  {==}
