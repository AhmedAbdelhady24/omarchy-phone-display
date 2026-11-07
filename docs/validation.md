# Validation notes

Environment checked on 2026-11-07: Omarchy 4.5.0, Hyprland 0.56.2,
Quickshell 0.3.2.r7, WayVNC 0.10.2, Android AVNC 3.3.1 on a Xiaomi Mi 9T.

The initial full-width failure was an orientation/aspect mismatch: a portrait
1080×2400 virtual framebuffer was viewed on the landscape phone. A screen-width
check on an ADB screenshot found desktop content covering 45% of the width.
After setting the monitor to the phone's native landscape 2340×1080, the same
check found 100% width coverage. Screenshots remain outside this repository.
The native-resolution and orientation lifecycle regression reproduces the
relevant dimensions through the actual backend command path.

Automated checks cover missing AVNC, native phone resolution, orientation
changes, live monitor placement, ADB charging-awake on/off, USB authorization,
collisions, failed-start rollback, process ownership, and concurrent toggles.
Pure layout tests cover all four placement edges, multiple monitors,
non-overlap, negative coordinates, and orientation geometry. Test doubles do
not interact with real USB hardware or the compositor.

The widget and lazy popup content are also instantiated in a separate
Quickshell process on the supported session. This catches QML type/import
errors that the manifest validator cannot detect. The installed popup was checked after a shell restart. Upgrading the loaded
1.0 widget to the new shared QML module required that one-time restart.

Live checks must include AVNC client connection, correct monitor geometry,
loopback-only listener, USB reverse mapping, and stop cleanup. Manually
dragging the real popup remains a separate interaction check; simulated
input tests cannot certify all pointer devices. On the connected phone, the
active session was observed switching from 1080×2340 portrait to 2340×1080
landscape through the watcher, with the left monitor edge staying attached.
An ADB screenshot after the update again measured 100% width coverage.
The live setup probe detected AVNC, and Android reported the charging-awake
preference enabled after the explicit ADB command.

Still unmeasured: sustained frame rate and end-to-end latency. Display mode
refresh rate and a connected VNC client do not prove a playback frame rate.
Keep the upstream output-removal/fallback caveat in the README visible.

The 1.2 UI uses compact expandable setup cards and theme-derived surfaces.
An isolated Quickshell check confirmed two live accent changes without a reload,
automatic expansion when AVNC is missing, and collapsed steps once checks pass.
The contrast regression checks black/white selected text across 4,096 accents.

Updated documentation captures render the actual popup content component in a
temporary, isolated headless preview. Setup state comes from the connected
phone, and the layout excludes the capture output. The GIF illustrates compact
checks, expanded USB guidance, controls, and isolated mint/blue accent changes.
The capture helper and its temporary IPC hook are not part of the plugin.
