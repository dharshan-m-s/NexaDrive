# Diagnosis: the "yellow/green underline under every line of text" report

**Status: closed — not a NexaDrive typography bug.**

## Report

Screenshots of *Settings → Users* and *Settings → Update center* showed what
looked like a thin yellow/green line beneath almost every line of text.

## Conclusion

The lines are **Flutter's debug baseline visualisation**, not application
typography. They are drawn only when `debugPaintBaselinesEnabled` is `true`,
which the Flutter Inspector / DevTools exposes as a toggle ("Paint baselines").
Nothing in the NexaDrive codebase sets it, and it **cannot appear in a release
build**.

## Evidence

### 1. The paint sites are `assert`-gated

`packages/flutter/lib/src/rendering/box.dart`, `RenderBox.debugPaintBaselines`:

```dart
void debugPaintBaselines(PaintingContext context, Offset offset) {
  assert(() {
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 0.25;
    // ideographic baseline
    if (baselineI != null) {
      paint.color = const Color(0xFFFFD000);   // amber
      ...
    }
    // alphabetic baseline
    if (baselineA != null) {
      paint.color = const Color(0xFF00FF00);   // green
      ...
    }
    return true;
  }());
}
```

Two things follow directly:

- The colours are **green (`0x00FF00`) and amber (`0xFFFFD000`)** — i.e. exactly
  the "yellow/green-looking lines" that were reported.
- The whole body is inside `assert(() { … }())`. Dart strips `assert` bodies in
  release mode, so this code is compiled out. A release build physically cannot
  render these lines.

The call site is likewise guarded, in `RenderBox.paint`
(`packages/flutter/lib/src/rendering/box.dart`):

```dart
if (debugPaintBaselinesEnabled) {
  debugPaintBaselines(context, offset);
}
```

`debugPaintBaselinesEnabled` is declared `false` by default
(`packages/flutter/lib/src/rendering/debug.dart:39`) and is only reachable from
the app through the rendering service extension the Inspector drives
(`rendering/service_extensions.dart`, `rendering/binding.dart`).

### 2. Nothing in the repository enables it

```
$ grep -rniE "(baseline|debugPaint)" app/lib   # -> no matches
```

`app/lib` contains **no** `TextDecoration` usage at all, so there is no
underline in the design system either.

### 3. Reproduced and isolated on the reported screens

`AdminUsersScreen` and the Update center header were rendered to PNG twice —
once with baseline painting off, once on — with everything else identical. The
images are kept in `doc/diagnostics/`:

| File | Baseline painting | Yellow/green lines |
| --- | --- | --- |
| `users_off.png` | off | no |
| `users_on.png` | on | **yes** |
| `update_off.png` | off | no |
| `update_on.png` | on | **yes** |

Diffing the colour histograms, the colours that appear **only** in the
baseline-painting-on renders are:

- **83 distinct green-family blends** with the blue channel near zero
  (`#66CB05`, `#6CEB02`, `#70E902`, `#71EC02`, …) — antialiased blends of
  `0x00FF00`.
- **116 distinct amber-family blends** with red and green both far above blue
  (`#D7F8B0`, `#C0F691`, `#C9F7A7`, …) — antialiased blends of `0xFFFFD000`.

The off renders contain **zero** pixels from either family.

### 4. The framework itself flags this as a debug-only variable

Running a test that leaves the flag set fails with:

```
The value of a rendering debug variable was changed by the test.
  debugAssertAllRenderVarsUnset (package:flutter/src/rendering/debug.dart:348)
```

Flutter treats these flags as state that must not survive normal execution.

## Debug vs release

- **Debug** (`flutter run`, `flutter test`): asserts are live, so if the flag is
  toggled the lines appear. Removing the toggle removes them.
- **Release** (`flutter build … --release`): `assert` bodies are stripped, so
  the lines cannot be rendered under any circumstance.

Both builds were produced from this tree during verification (see the
engineering report), and the release pipeline compiles the identical theme and
widget code paths — there is no conditional typography anywhere in `app/lib`.

## What changed as a result

Nothing in the UI needed to change for this. To stop it being mis-filed as a
typography regression again, `app/test/debug_rendering_guard_test.dart` now
asserts that:

1. no rendering debug variable is left enabled, and
2. no source file under `lib/` enables a debug paint flag, and
3. no `TextStyle` reachable from the light or dark `ThemeData` carries an
   underline decoration.

## If you see the lines again

They are a *session* setting on the running debug app, not stored in the repo:

- In DevTools, close the **Flutter Inspector** panel's "More actions" menu and
  untick **Paint baselines**.
- Or hot-restart / relaunch with `flutter run` — the flag is not persisted.
- To confirm instantly: `flutter build linux --release` (or install a release
  APK) and look at the same screen. The lines will be gone.
