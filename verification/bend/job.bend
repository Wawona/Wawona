import Base

# Models of the Rust helpers. Not linked into Wawona.
# start/stop: src/core/machine_phase.rs
# nav: src/core/nav_place.rs (one level, same nesting as app.contract routes)
# clamp: non-negative axis of src/core/invariants.rs clamp_rect
# port: src/domain/sanitize_ssh_host.rs normalize_ssh_port
# the Bool and Nat predicates: src/core/wayland/protocol_proofs.rs
# keyboard eligibility: crates/wawona-laws focus.rs

type Phase is Data:
  Idle{}
  Running{}
  Stopped{}

def stop(phase: Phase) -> Phase:
  match phase:
    case Idle{}: Idle{}
    case Running{}: Stopped{}
    case Stopped{}: Stopped{}

def start(phase: Phase) -> Phase:
  match phase:
    case Idle{}: Running{}
    case Running{}: Running{}
    case Stopped{}: Running{}

# One catalog. Settings is a cover over Machines, not a peer tab root.
type Place is Data:
  Machines{}
  Machine{}
  Session{}
  Add{}
  CreateTag{}
  Tabs{}
  Settings{}
  Section{}

def back(place: Place) -> Place:
  match place:
    case Machines{}: Machines{}
    case Machine{}: Machines{}
    case Session{}: Machines{}
    case Add{}: Machines{}
    case CreateTag{}: Machines{}
    case Tabs{}: Machines{}
    case Settings{}: Machines{}
    case Section{}: Settings{}

def select_machines(place: Place) -> Place:
  match place:
    case Machines{}: Machines{}
    case Machine{}: Machines{}
    case Session{}: Machines{}
    case Add{}: Machines{}
    case CreateTag{}: Machines{}
    case Tabs{}: Machines{}
    case Settings{}: Machines{}
    case Section{}: Machines{}

def select_settings(place: Place) -> Place:
  match place:
    case Machines{}: Settings{}
    case Machine{}: Settings{}
    case Session{}: Settings{}
    case Add{}: Settings{}
    case CreateTag{}: Settings{}
    case Tabs{}: Settings{}
    case Settings{}: Settings{}
    case Section{}: Settings{}

def open_machine(place: Place) -> Place:
  match place:
    case Machines{}: Machine{}
    case Machine{}: Machine{}
    case Session{}: Machine{}
    case Add{}: Machine{}
    case CreateTag{}: Machine{}
    case Tabs{}: Machine{}
    case Settings{}: Machine{}
    case Section{}: Machine{}

def open_section(place: Place) -> Place:
  match place:
    case Machines{}: Section{}
    case Machine{}: Section{}
    case Session{}: Section{}
    case Add{}: Section{}
    case CreateTag{}: Section{}
    case Tabs{}: Section{}
    case Settings{}: Section{}
    case Section{}: Section{}

# clamp_origin = min(x, limit). clamp_span is the width that still fits.
# clamp_right = origin + span. For x, span, limit >= 0 this is the x axis of clamp_rect.

def clamp_origin(+x: Nat, +limit: Nat) -> Nat:
  Nat.min(x, limit)

def clamp_span(+limit: Nat, +x: Nat, +span: Nat) -> Nat:
  match limit:
    case 0n:
      0n
    case 1n+lp:
      match x:
        case 0n:
          match span:
            case 0n:
              0n
            case 1n+sp:
              1n+clamp_span(lp, 0n, sp)
        case 1n+xp:
          clamp_span(lp, xp, span)

def clamp_right(+x: Nat, +span: Nat, +limit: Nat) -> Nat:
  Nat.add(clamp_origin(x, limit), clamp_span(limit, x, span))

def in_port(+n: Nat) -> Bool:
  Bool.and(Nat.is_ge(n, 1n), Nat.is_le(n, 65535n))

def normalize_port(flag: Bool, raw: Nat, fallback: Nat) -> Nat:
  match flag:
    case True{}:
      raw
    case False{}:
      fallback

def normalize(+raw: Nat, fallback: Nat) -> Nat:
  normalize_port(in_port(raw), raw, fallback)

# fetch_add(1) on one thread. Interleaving stays on the Loom counter.
def bump(n: Nat) -> Nat:
  1n+n

# size * 3 * sizeof(u16) = size * 6. gamma_ramp_byte_len_matches.
def gamma_bytes(size: Nat) -> Nat:
  Nat.mul(size, 6n)

# fractional_scale_units_at_least_120. centi * 120 / 100, then at least 120.
def quot(p: Nat & Nat) -> Nat:
  match p:
    case (q, r):
      q

def scale_units(+centi: Nat) -> Nat:
  Nat.max(120n, quot(Nat.divmod(Nat.mul(centi, 120n), 100n)))

# idle_inhibit_map_remove_clears. saturating_sub(1) when removed.
def idle_remove(before: Nat, removed: Bool) -> Nat:
  match removed:
    case False{}:
      before
    case True{}:
      Nat.sub(before, 1n)

# commit_timing_hold_required.
def hold_required(+target: Nat, +now: Nat) -> Bool:
  Nat.is_gt(target, now)

# wlr_input_inhibit, gamma, color-representation, image-copy, hyprland shortcut, wl_shell role.
def rejects_second(already: Bool) -> Bool:
  already

# pointer_constraint_oneshot_stays_dead. Defunct must not become active.
def oneshot_allows(defunct: Bool, active: Bool) -> Bool:
  Bool.not(Bool.and(defunct, active))

# fifo_barrier_blocks_next_commit.
def fifo_blocks(armed: Bool, presented: Bool) -> Bool:
  Bool.and(armed, Bool.not(presented))

# output_power_mode_is_on_or_off and tearing_hint_is_vsync_or_async.
def bit_ok(mode: Nat) -> Bool:
  match mode:
    case 0n:
      True{}
    case 1n+p:
      match p:
        case 0n:
          True{}
        case 1n+rest:
          False{}

# color_representation_alpha_mode_supported. 0, 1, 2.
def alpha_ok(mode: Nat) -> Bool:
  match mode:
    case 0n:
      True{}
    case 1n+p:
      match p:
        case 0n:
          True{}
        case 1n+q:
          match q:
            case 0n:
              True{}
            case 1n+rest:
              False{}

# content_type_hint_is_known_or_none. 0 none, 1 photo, 2 video, 3 game.
type Hint is Data:
  HintNone{}
  Photo{}
  Video{}
  Game{}
  Other{}

def content_ok(hint: Hint) -> Bool:
  match hint:
    case HintNone{}: True{}
    case Photo{}: True{}
    case Video{}: True{}
    case Game{}: True{}
    case Other{}: False{}

# cursor_shape_value_is_non_zero.
def cursor_ok(shape: Nat) -> Bool:
  match shape:
    case 0n:
      False{}
    case 1n+rest:
      True{}

# single_pixel_buffer_is_one_by_one.
def one_by_one(w: Nat, h: Nat) -> Bool:
  match w:
    case 0n:
      False{}
    case 1n+wp:
      match wp:
        case 0n:
          match h:
            case 0n:
              False{}
            case 1n+hp:
              match hp:
                case 0n:
                  True{}
                case 1n+rest:
                  False{}
        case 1n+rest:
          False{}

# viewport destination and xdg positioner size: both positive.
# Unset destination (both -1 in Rust) is the True flag.
def size_positive(w: Nat, h: Nat) -> Bool:
  match w:
    case 0n:
      False{}
    case 1n+rest:
      match h:
        case 0n:
          False{}
        case 1n+hp:
          True{}

def dest_valid(unset: Bool, w: Nat, h: Nat) -> Bool:
  match unset:
    case True{}:
      True{}
    case False{}:
      size_positive(w, h)

# Keyboard-eligible windows. Closing removes the id. Selecting a missing id
# stays unset. clear drops focus when it is the closed id.

type Ids is Data:
  Empty{}
  Link{ wid: Nat, rest: Ids }

def same(a: Nat, b: Nat) -> Bool:
  match a b:
    case 0n 0n:
      True{}
    case 0n 1n+bp:
      False{}
    case 1n+ap 0n:
      False{}
    case 1n+ap 1n+bp:
      same(ap, bp)

def found(eq: Bool, later: Bool) -> Bool:
  match eq:
    case True{}:
      True{}
    case False{}:
      later

def in(ids: Ids, +id: Nat) -> Bool:
  match ids:
    case Empty{}:
      False{}
    case Link{ wid, rest }:
      found(same(id, wid), in(rest, id))

def keep(eq: Bool, head: Nat, tail: Ids) -> Ids:
  match eq:
    case True{}:
      tail
    case False{}:
      Link{ head, tail }

def without(ids: Ids, +id: Nat) -> Ids:
  match ids:
    case Empty{}:
      Empty{}
    case Link{ wid, rest }:
      +w = wid
      keep(same(id, w), w, without(rest, id))

type Focus is Data:
  Unset{}
  On{ cur: Nat }

def clear_go(a: Nat, b: Nat, cur: Nat) -> Focus:
  match a b:
    case 0n 0n:
      Unset{}
    case 0n 1n+bp:
      On{ cur }
    case 1n+ap 0n:
      On{ cur }
    case 1n+ap 1n+bp:
      clear_go(ap, bp, cur)

def clear(focus: Focus, +closed: Nat) -> Focus:
  match focus:
    case Unset{}:
      Unset{}
    case On{ cur }:
      +c = cur
      clear_go(c, closed, c)

def select_at(ok: Bool, id: Nat) -> Focus:
  match ok:
    case True{}:
      On{ id }
    case False{}:
      Unset{}

def select(ids: Ids, +id: Nat) -> Focus:
  select_at(in(ids, id), id)

# Exact actions. One contract for every ALL_TARGETS host.
# store is a settings write. flip is pin, sort, and tag.
# remote_on is setDraftSession: remote stays on only for waypipe.
# save_when is saveDetail / saveAdd / saveCreateTag: a blank name does not save.
# open_when is openSection: a hidden desktop section does not open.

def store(b: Bool) -> Bool:
  b

def flip(b: Bool) -> Bool:
  Bool.not(b)

def remote_on(waypipe: Bool, on: Bool) -> Bool:
  Bool.and(waypipe, on)

def save_when(named: Bool) -> Bool:
  named

def open_when(shown: Bool) -> Bool:
  shown

# wp_alpha_modifier: every factor is in range.
def factor_ok(n: Nat) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+p:
      True{}

# wp_drm_lease: an empty connector set is rejected.
def lease_empty(n: Nat) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+p:
      False{}

# zwlr_export_dmabuf without a capability, and shortcut inhibit cleared on destroy.
def absent(has: Bool) -> Bool:
  Bool.not(has)

# wp_viewporter: fractional source without a destination is rejected.
def frac_reject(has_dest: Bool, aligned: Bool) -> Bool:
  match has_dest:
    case True{}:
      False{}
    case False{}:
      Bool.not(aligned)
