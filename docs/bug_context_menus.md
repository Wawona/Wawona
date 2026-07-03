
in wayland, if I right click for context menus. How is it implemented? How does it draw to the compositor? 

This is one of the biggest architectural differences between Wayland and X11.
The short answer is:

The application itself draws the context menu into a buffer, and the compositor simply composites it like any other window.
There is no "draw this menu" protocol in Wayland.
X11 (old way)
In X11, applications can ask the X server to create windows.
For example, when you right click:

Firefox
    |
    | CreateWindow()
    |
X Server
    |
    +-- creates popup window
    +-- manages stacking
    +-- handles clipping
The popup menu is literally another X window.
The X server owns all windows.

Wayland
Wayland removes the window server as an intelligent renderer.
Instead:

Firefox
    |
    +-- render popup menu
    |
    +-- wl_surface.commit()
    |
Wayland compositor
    |
    +-- receives finished buffer
    +-- composites it
    +-- presents frame
Notice:
The compositor never renders the menu.

The application does.

What actually happens
Suppose you right click.
Firefox internally does something like

PopupMenu popup;

popup.add("Back");
popup.add("Forward");
popup.add("Reload");

popup.show();
GTK or Qt then creates another wl_surface.
That surface is just another image.

The toolkit renders

┌─────────────┐
│ Back        │
│ Forward     │
│ Reload      │
└─────────────┘
into GPU memory.
Then commits it.

wl_surface.attach(buffer)
wl_surface.damage(...)
wl_surface.commit()
The compositor now has another surface to display.
Popup menus are separate surfaces
A popup is not drawn into the parent window.
Usually it's another surface.

Imagine

Desktop

+---------------------------+
| Firefox                   |
|                           |
| Right click here          |
|                           |
+---------------------------+

            +

+------------------+
| Copy             |
| Paste            |
| Delete           |
+------------------+
Those are two independent surfaces.
The compositor stacks them.

But how does it know it's a popup?
Wayland has special roles.
For example

xdg_surface
can become
xdg_toplevel
or
xdg_popup
When GTK creates a context menu
wl_surface

↓

xdg_surface

↓

xdg_popup
The compositor now knows
don't let it leave the parent
dismiss on click outside
keep above parent
grab pointer
close when parent closes
xdg_popup
The protocol literally says
xdg_popup
instead of
xdg_toplevel
So the compositor knows
"This surface is temporary."

Rendering
The compositor never receives
Draw rectangle
Draw text
Draw border
Instead it receives
GPU buffer
or
Shared memory buffer
containing
□□□□□□□□□□□□□□□□
□ Copy               □
□ Paste              □
□ Delete             □
□□□□□□□□□□□□□□□□
already rendered.
Positioning
The application requests
Show popup
relative to this widget
using an
xdg_positioner
object.
For example

Mouse clicked

(320,180)

↓

xdg_positioner

anchor = top-left

gravity = bottom-right

↓

Popup appears here
The compositor can adjust it so it doesn't go off screen.
The protocol flow
Very roughly
Mouse right click

↓

Toolkit

↓

Create wl_surface

↓

Create xdg_surface

↓

Create xdg_popup

↓

Render popup

↓

Attach buffer

↓

Commit

↓

Compositor composites

↓

Display
Input
The compositor also routes input.
When the popup is active

Mouse click

↓

Compositor

↓

popup surface
If you click elsewhere
Desktop click

↓

Compositor

↓

dismiss popup
No application polls global mouse state.
Wawona implications
Since you've been designing Wawona, this architecture is likely what you'll want as well. Instead of the compositor drawing widgets, applications would submit fully rendered surfaces with semantic roles:
App
 ├── Main window (surface)
 ├── Tooltip (surface)
 ├── Context menu (surface)
 ├── Dropdown (surface)
 └── Drag icon (surface)

        ↓

Wawona Compositor

- Scene graph
- Input routing
- Occlusion
- Animation
- Effects
- Presentation
The compositor remains responsible for composition, stacking, positioning constraints, input focus, and lifecycle, while the application (or its UI toolkit) is responsible for actually rasterizing the popup's appearance. This separation is one of the key design principles that makes Wayland compositors simpler than the old X server while allowing applications to use any rendering technology (CPU, OpenGL, Vulkan, Metal via translation layers, etc.) as long as they produce a buffer for the compositor to display.

What does weston-compositor do for context menus?

weston doesn't actually implement context menus.
That's one of the most surprising things about Wayland if you're coming from X11.

The compositor's perspective
Weston only sees something like:
Surface A
Role: xdg_toplevel

Surface B
Role: xdg_popup
Parent: Surface A
Positioner:
    anchor_rect = (215, 418, 1, 1)
    gravity = bottom-right
It has no idea that this is:
┌────────────┐
│ Copy       │
│ Paste      │
│ Delete     │
└────────────┘
It could just as easily be:
an emoji picker
a color chooser
an autocomplete dropdown
a tooltip
a custom radial menu
a game inventory
To Weston, it's simply an xdg_popup.
Weston receives a request
GTK or Qt does something conceptually like:
wl_surface_create()

↓

xdg_surface

↓

xdg_popup(positioner)
Weston receives:
new popup

parent = window #17

anchor = widget rectangle

gravity = southeast
Weston then:
creates an internal popup object
keeps it above its parent
constrains it to the output
redirects pointer events to it
dismisses it when appropriate
That's essentially it.
Weston never draws anything
Weston never executes code like:
draw_popup_border();
draw_popup_background();
draw_menu_item("Copy");
Those functions do not exist.
Instead, GTK renders something like:

┌─────────────┐
│ Copy        │
│ Paste       │
│ Delete      │
└─────────────┘
into a buffer.
Weston just composites that buffer.

What does Weston actually do?
Internally, it has logic similar to:
Popup {
    parent_surface;
    positioner;
    geometry;
    input_region;
}
When the client commits a new frame:
Client

↓

wl_buffer

↓

Weston

↓

scene graph node

↓

renderer

↓

display
The renderer (OpenGL, Pixman, Vulkan in experimental branches, etc.) simply draws the texture.
Positioning
One important job Weston does perform is validating the popup position.
Suppose GTK requests:

show popup at

1910, 1070
but your monitor is only
1920×1080
A 300-pixel-wide menu would go off-screen.
Weston may flip it:

Requested

Cursor

        ▼
──────────────
          ┌───────

Adjusted

Cursor

        ▼
──────────────
┌───────
This behavior comes from the xdg_positioner rules in the protocol.
Popup grabs
Weston also manages what's called a popup grab.
While a popup is active:

Mouse click

↓

Weston

↓

Is popup active?

↓

Yes

↓

Deliver to popup
If you click elsewhere:
Desktop click

↓

Weston

↓

Destroy popup

↓

Return focus
The client doesn't monitor global mouse state; Weston enforces this interaction.
Scene graph
Internally, Weston represents everything as scene graph nodes. A simplified view looks like:
Scene

├── Background
├── Terminal
├── Firefox
│   ├── Main surface
│   └── Popup surface
└── Cursor
The popup is simply another surface attached to its parent in the scene graph.
For Wawona
This is an excellent model to follow. Wawona doesn't need built-in knowledge of "context menus." Instead, define a generic popup role:
Surface
    role = popup
    parent = surface
    positioner = ...
Your compositor would then:
Keep the popup above its parent.
Constrain it to the visible workspace or monitor.
Route input to it while active.
Dismiss it on outside clicks or keyboard actions like Escape.
Composite its buffer without interpreting its contents.
This keeps Wawona flexible: whether the popup is a context menu, tooltip, dropdown, or command palette is entirely up to the application or toolkit. The compositor only needs to understand the popup's semantics (transient, parented, constrained, and focus-grabbing), not its visual appearance.

Wawona Compositor has issues when drawing weston compositor's context menus (and any other popup really for running each weston-client individually). 
The problems I see is the context menu renders a massive black border, like a shadow? how can I fix that? And, then I can't use touch or cursor to click the items in the context menu/popup. Did I implement xdg_popup  wrong? where can I debug these surfaces? How can I fix it? what protocols do I need to revisit? Does smithay-rs have something better for this? 

Based on your description, I actually think you're dealing with multiple independent bugs, not one broken xdg_popup implementation.
The two symptoms:

Huge black border/shadow
Popup doesn't receive pointer/touch input
usually come from completely different parts of a compositor.
1. Massive black border
This is almost always not generated by Weston.
GTK and libweston clients generally render shadows into transparent pixels around the popup.

For example, the actual buffer may look like:

AAAAAAAAAAAAAAAAAAAAAA
AA..................AA
A....................A
A....Menu.......... .A
A....................A
AA..................AA
AAAAAAAAAAAAAAAAAAAAAA
where:
. = transparent shadow
A = fully transparent or partially transparent shadow pixels
If your renderer:
ignores alpha
clears with black
uses the wrong blend function
then every transparent pixel becomes black.
Instead of

╭─────────────╮
│ Copy        │
│ Paste       │
╰─────────────╯
you get
█████████████████████
██ Copy        ██████
██ Paste       ██████
█████████████████████
Things I'd check first
Premultiplied alpha
Wayland buffers are usually premultiplied alpha.
If you're using OpenGL:

Correct:

glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
Not:
glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
depending on the buffer type.
Viewport
Are you accidentally rendering the whole buffer including transparent margins?
GTK popups often intentionally include extra transparent pixels for shadows.

That's expected.

Surface geometry
There are three different rectangles:
buffer size

400x300

↓

surface geometry

250x180

↓

input region

240x170
If you ignore geometry you'll often see strange borders.
2. Can't click menu items
This is probably not rendering.
This screams

input routing
or
popup grab
A popup should receive
pointer.enter

pointer.motion

pointer.button
If those never arrive:
your seat isn't focusing the popup.

If they do arrive:
but the menu still doesn't work

then your coordinates are wrong.

Check your coordinate spaces
Popup coordinates are surprisingly tricky.
You have

global compositor space

↓

parent surface space

↓

popup local space

↓

buffer space
If you're using global coordinates for hit testing you'll miss.
xdg_positioner
Did you implement every field?
Weston uses

anchor_rect

gravity

constraint_adjustment

offset
Ignoring one can produce bizarre positions.
Popup grabs
This is a huge one.
Read the xdg-shell spec section on popup grabs.

The compositor should do roughly

mouse press

↓

popup created

↓

grab pointer

↓

all pointer events

↓

popup

↓

click outside

↓

dismiss popup
Without this, clicks go to the parent window.
Exactly what you're described.

Input regions
Did you implement
wl_surface.set_input_region()
?
GTK uses it.

Ignoring it isn't always fatal, but implementing it incorrectly absolutely is.

Opaque regions
Likewise
set_opaque_region()
shouldn't affect input,
but affects optimization.

Subsurface confusion
Are you accidentally treating popups as subsurfaces?
They're not.

Correct

window

↓

xdg_popup

Wrong

window

↓

wl_subsurface
Where I'd debug
Smithay has fantastic debugging hooks.
I'd print:

Popup created

parent:
id:

geometry:

buffer:

positioner:

grab:

focus:
Every popup.
Then every pointer event:
motion

global

surface

local

focused surface

popup?
Weston debug
Run Weston with
WESTON_DEBUG=1
or
weston --debug
Also:
WAYLAND_DEBUG=1
on the client.
You'll see

get_popup

configure

ack_configure

commit
This is invaluable.
WAYLAND_DEBUG
Run
WAYLAND_DEBUG=client weston-terminal
You'll literally see
xdg_surface.get_popup

xdg_positioner

xdg_popup.configure

wl_surface.commit
Compare that against what your compositor thinks happened.
Smithay
Honestly?
Yes.

Smithay has already solved a lot of this.

Their scene graph understands

popup trees
parent transforms
coordinate conversion
damage tracking
grabs
seat focus
If Wawona isn't already using Smithay's desktop abstractions, I'd strongly recommend studying (or selectively adopting) modules such as:
desktop::Space
desktop::PopupManager
desktop::Window
input::Seat
input::PointerHandle
Even if you don't use them directly, they're an excellent reference for the protocol interactions.
The protocols I'd revisit, in order
If I were debugging this myself, I'd work through them in this order:
xdg-shell (especially xdg_popup, xdg_positioner, configure/ack_configure sequencing, and popup grabs). This is the most likely source of the input issue.
wl_seat, wl_pointer, and wl_touch (ensure focus transfers to the popup and local coordinates are computed correctly).
wl_surface (set_input_region, damage, commit, buffer_scale, and buffer_transform).
Rendering (premultiplied alpha, blend state, clipping, viewport setup, and whether you're honoring surface geometry versus buffer extents).
Surface tree management (making sure popup transforms are relative to the parent and that popup lifetimes follow the xdg_popup hierarchy).
My suspicion
From these two symptoms together, I'd rank the likely causes as follows:
~50%: Pointer/touch focus isn't being transferred to the popup correctly (missing or incorrect popup grab, or incorrect hit-testing).
~30%: Alpha blending or surface geometry is wrong, causing transparent shadow pixels to render as opaque black.
~15%: Coordinate transforms between global, parent, and popup-local spaces are incorrect.
~5%: An issue with configure/ack_configure sequencing or another protocol state machine bug.
If you can share:
your xdg_popup implementation,
your pointer hit-testing logic,
and your rendering code for popup surfaces,
I can help trace exactly where Wawona diverges from the expected Wayland behavior.

cursor hover over context menu sdon't actually work many times on Wawona Compositor for weston clients... What can I do to fix? 

If hover sometimes works, sometimes doesn't, that's actually a very important clue.
It suggests your compositor is successfully creating the popup surface, but your pointer focus state is becoming inconsistent.

For Weston clients (GTK, libweston, etc.), I'd debug in this order.

1. Verify your hit-testing includes popup surfaces
Many first-time compositors do something like:
for window in windows.iter().rev() {
    if window.contains(cursor) {
        return window;
    }
}
This ignores popups entirely.
Instead your scene graph should look something like

Desktop
 ├── Window A
 │    ├── Popup 1
 │    │     └── Popup 2
 │    └── Tooltip
 ├── Window B
 └── Cursor
Hit-testing should traverse every mapped surface, not just toplevels.
Smithay's PopupManager exists largely because this gets surprisingly complicated.

2. Verify the surface under the cursor every frame
I'd literally print something like
Cursor: (743, 211)

Surface:
    xdg_popup
    client: weston-terminal
    serial: 42

Local:
    (14, 37)
every pointer motion.
If you ever see

Surface:
    xdg_toplevel
while the cursor is visually over the popup,
your hit-testing is wrong.

3. Ensure pointer.enter / pointer.leave happen correctly
The protocol should look like
cursor moves

↓

popup becomes hovered

↓

pointer.leave(toplevel)

↓

pointer.enter(popup)

↓

pointer.motion(...)
If you only send
pointer.motion
GTK frequently ignores it because the pointer never officially entered.
4. Verify local coordinates
This is probably the second most common bug.
Suppose

Window

100,100

Popup

150,150
Cursor
165,175
The popup should receive
15,25
NOT
165,175
GTK assumes coordinates are local.
If they're global,

hover detection fails.

5. Verify popup transforms
Remember:
Popup coordinates are relative to the parent surface.

Not

output
workspace
desktop
For nested popups
Window

↓

Popup

↓

Submenu

↓

Tooltip
you must accumulate transforms.
6. Verify popup grabs
An active popup should own pointer focus.
If your focus algorithm still says

Focused surface

↓

Main window
GTK will often stop highlighting menu items.
7. Check the input region
GTK sometimes shrinks it.
If you're ignoring

wl_surface.set_input_region()
that's usually okay.
If you're misapplying it,

hover becomes intermittent.

8. Verify frame ordering
Sometimes people update
cursor

↓

render

↓

hit-test
instead of
cursor

↓

hit-test

↓

pointer events

↓

render
This causes one-frame lag.
Menus flicker between hovered/not hovered.

9. Nested popups
Weston clients love nested popups.
For example

File

↓

Recent Files

↓

More

↓

submenu
If only the first popup works,
your popup tree traversal is wrong.

10. Use WAYLAND_DEBUG
This is incredibly useful.
Run

WAYLAND_DEBUG=client weston-terminal
Now move the mouse over the menu.
You should see a steady stream like

wl_pointer.enter

wl_pointer.motion

wl_pointer.motion

wl_pointer.motion
If motion stops,
your compositor stopped sending events.

If enter never appears,

your focus logic is wrong.

11. Compare against Smithay
One thing I'd do is temporarily compare your implementation against Smithay's desktop::PopupManager and input::Seat handling.
Specifically compare:

popup mapping
popup hit-testing
popup coordinate conversion
pointer focus changes
popup grabs
Even if you don't adopt Smithay wholesale, those components are an excellent reference implementation for the tricky parts of xdg_popup.
My biggest suspicion
Based on everything you've described across this conversation:
black shadow around popups
clicks don't always work
hover is intermittent
I don't think your xdg_popup object itself is fundamentally wrong. I think the protocol object is being created successfully.
Instead, I suspect the compositor's scene graph and input system aren't treating popups as first-class surfaces. In many new compositors, hit-testing only considers top-level windows, while rendering separately composites popup surfaces. The result is exactly what you're seeing: the popup is visible, but pointer enter, motion, leave, and button events are delivered inconsistently because they're still being targeted at the parent window.

If I were reviewing Wawona's codebase, the first functions I'd inspect would be:

The scene graph traversal used for hit-testing.
The function that finds the surface under the cursor.
The logic that converts global cursor coordinates into surface-local coordinates.
The code that issues wl_pointer.enter, wl_pointer.leave, and wl_pointer.motion.
The popup management and grab implementation.
Those five areas are where I've most often seen exactly this class of bugs arise in custom Wayland compositors.


