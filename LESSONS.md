# Lessons Learned — Session 1 (2026-06-29)

First session: built the game from an empty Godot project to a working Android
deploy.

## Godot + Claude Code workflow

- **Claude writes `.tscn` files as text**, but the Godot editor reformats them
  on open (strips `load_steps`, adds `uid` fields, adds `unique_id` to nodes).
  This is normal — don't fight it. Let the editor rewrite the file and treat
  its version as canonical.
- **Claude can't press Play.** Every code change needs the developer to run and
  report back. Flag anything that could fail at runtime rather than assuming it
  works.
- **The desktop window was taller than the screen.** A 720×1280 viewport
  produced a window that overflowed the monitor, hiding the speed buttons
  entirely. Fix: set `window_width_override` / `window_height_override` in
  `project.godot` to a smaller size (480×854) while keeping the game viewport
  at the full mobile resolution.

## GDScript / Godot 4.7 specifics

- **`class_name` vs autoload — pick one.** If a script uses `class_name Foo`,
  registering it as an autoload named `Foo` causes a "hides an autoload
  singleton" error. Pure static utility classes should use `class_name` only
  (no autoload), since they don't extend `Node` and can't be autoloaded anyway.
- **Autoloads must extend `Node`.** A script with only static functions can't
  be an autoload. Use `class_name` to make it globally accessible instead.
- **The editor re-adds autoloads.** If an autoload was registered and then
  removed from `project.godot` by hand, the editor may re-add it from its
  cache. Remove it via **Project → Project Settings → Autoload** and restart
  the editor to fully clear it.
- **Full-screen UI eats input.** A `Control` node anchored to full-rect on a
  `CanvasLayer` intercepts all mouse/touch events by default. Set
  `mouse_filter = MOUSE_FILTER_IGNORE` recursively on all non-interactive
  nodes so clicks pass through to the game layer beneath.

## Android export

- **One-time setup is the bulk of the work.** Installing Android Studio, the
  SDK, command-line tools, JDK, export templates, and configuring paths in
  Editor Settings takes longer than the actual export.
- **Android Studio's bundled JDK lives at `<install>/jbr`**, not in a folder
  called `jdk`. It works fine as the Java SDK Path in Godot's editor settings.
- **Wireless ADB works well** once paired. No USB cable needed. Pair once via
  `adb pair`, then `adb connect` on subsequent sessions.
- **One-click deploy passes `--remote-debug localhost`**, which fails over
  wireless (the phone's localhost isn't the PC). Use **Project → Export →
  Export Project** for a manual APK instead. The manual APK runs without the
  remote debug flag and works reliably.
- **`Polygon2D` didn't render on Android.** Programmatically setting the
  `polygon` and `color` properties on a `Polygon2D` node worked on desktop but
  produced invisible tiles on a Samsung/Adreno GPU. Switching to `Node2D` with
  `draw_colored_polygon()` in `_draw()` fixed it. Prefer `_draw()` for
  runtime-generated geometry.
- **Enable ETC2/ASTC texture compression** in Project Settings before
  exporting — Android requires it and the export dialog will warn if it's
  missing.
