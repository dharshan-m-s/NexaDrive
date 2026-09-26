# Diagnosis: the "yellow double underline under page titles" report

**Status: fixed — real cause found and corrected on 2026-09-26.**

## Report

*Settings → Users* and *Settings → Update center* rendered a thin **pure-yellow
double line** directly beneath the page title. Every other screen was clean.
The lines were visible in an installed, non-debuggable **release** APK.

## Root cause

Flutter's deliberate fallback `DefaultTextStyle` for text that is **not inside a
`Material`**:

`packages/flutter/lib/src/material/app.dart:45`

```dart
const TextStyle _errorTextStyle = TextStyle(
  color: Color(0xD0FF0000),
  fontFamily: 'monospace',
  fontSize: 48.0,
  fontWeight: FontWeight.w900,
  decoration: TextDecoration.underline,
  decorationColor: Color(0xFFFFFF00),          // the reported pure yellow
  decorationStyle: TextDecorationStyle.double, // the reported double line
  debugLabel: 'fallback style; consider putting your text in a Material',
);
```

`MaterialApp` installs this as the ambient `DefaultTextStyle`. It is a
deliberate developer-facing diagnostic, not a bug in Flutter: the intent is that
text rendered outside a `Material` is impossible to miss.

A `Text` widget resolves `decoration` from the **ambient** `DefaultTextStyle`
whenever its own style does not set one. `AppTextStyle.pageTitle` sets
`fontSize`/`fontWeight`/`letterSpacing` but **not** `decoration`, so the title
transparently inherited `TextDecoration.underline` with `decorationColor`
`0xFFFFFF00` and `decorationStyle: double`.

### Why only these two screens

`OneUiPage` renders the title and subtitle. Whether they inherit a real text
style depends entirely on whether the route supplies a `Material`:

| Screen | `Scaffold` of its own | `Material` ancestor | Result |
| --- | --- | --- | --- |
| Users | no | none | **yellow double underline** |
| Update center | no | none | **yellow double underline** |
| Audit log | yes | yes | clean |
| Settings, Home, Sync center, … | yes (shell `Scaffold`) | yes | clean |

`app_shell.dart` wraps shell tabs in a `Scaffold`, and the other routed pages
bring their own, so their text already resolved against a `Material`. Users and
Update Center are pushed as bare `MaterialPageRoute`s returning `OneUiPage`
directly, with no `Scaffold` anywhere above them — so they were the only screens
where the fallback was reachable.

## Fix

`OneUiPage` now provides a transparent `Material`:

```dart
return Material(
  type: MaterialType.transparency,
  child: Column(/* ... */),
);
```

`Material` installs `AnimatedDefaultTextStyle(Theme.of(context).textTheme.bodyMedium!)`
(`material.dart:476`) for every material type, including `transparency`, which
paints no background. The fix is structural — it removes the fallback rather
than masking it — and it protects any future page that uses `OneUiPage` without
its own `Scaffold`.

Verified on a physical device (SM_M107F, Android 11, DPR 1.75): 0 pure-yellow
pixels on Users and Update Center, with Impeller (the shipping default
renderer) enabled. All 328 tests pass, including the committed goldens.

## Why earlier passes got this wrong

This document previously concluded the lines were the **debug baseline
overlay** and that "a release build physically cannot render these lines".
That was wrong, and the reasoning had a specific flaw: it noted the paint site
is gated by `if (debugPaintBaselinesEnabled)` but treated the flag as
authoritative, while `debugPaintBaselines`' entire body is itself wrapped in
`assert(() { ... }())` (`rendering/box.dart:3250`) and is compiled out of
release. The green pixels that seemed to confirm the theory were an artefact of
an over-loose colour threshold catching antialiased glyph edges on a dark
background. Two other theories were also tested and eliminated by measurement:
disabling Impeller, and device developer options.

The lesson recorded as a test: the existing decoration checks all wrapped the
screen in `Scaffold(body: screen)`, which supplies a `Material` and therefore
**hid the bug from every prior verification**. `test/text_decoration_regression_test.dart`
now also pumps these screens through `pumpRouted`, which renders them as a bare
route with no `Scaffold` — the shape the app actually ships. Those four tests
fail without the fix and pass with it.

## Guard

`app/test/text_decoration_regression_test.dart` pins both cases:

1. Screens wrapped in a `Scaffold` — existing coverage.
2. Screens rendered as a bare route with no `Scaffold` (`pumpRouted`) — the
   case that actually reproduced the report.

It also continues to assert that no rendering debug flag is set during a normal
render and that no `AppTextStyle` token carries a decoration.
