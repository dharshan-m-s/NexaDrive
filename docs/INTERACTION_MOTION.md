# NexaDrive Interaction & Motion Specification

> How the app moves and responds. Derived from Samsung One UI restraint and the
> Apple design methodology used strictly as a review lens (AGENTS.md), translated
> to Flutter's animation stack. All motion values live in `core/design/app_motion.dart`.

## 1. Motion model

One UI motion is restrained, confident, physical. Defaults:

| Parameter | Value | Applies to |
|---|---|---|
| response | 0.35 s | sheet settle, page transitions, hero states |
| damping | 1.0 (critically damped, no overshoot) | default UI motion |
| damping | ~0.8 | ONLY momentum-driven gestures (a swipe release that throws) — reserve bounce for flick, never for fade-ins |

Spring params resolved in `app_motion.dart` as `SpringDescription(mass: 1.0,
stiffness: 8.1633, damping: 5.7143)` (response 0.35 / damping 1.0) and a faster
`microSpring` for press feedback.

## 2. Durations & curves (tokens)

- `micro` 120ms — press highlight, toggle, checkbox.
- `fast` 180ms — row highlight, icon swap, counters, switchers.
- `normal` 300ms — sheet slide, page transitions, expand/collapse.
- `slow` 380ms — deliberate navigation motion.
- Curves: `standard` (responsive feel), `enter` / `exit` (mirrored for spatial
  consistency: things enter and leave along the same path), `fade` (opacity).

## 3. Movement language (mapped from the Apple methodology review lens)

| Principle | Flutter implementation |
|---|---|
| Respond on pointer-down, not release | `InkWell` press states surface on touch-down by default; scrim/overlay widgets in the library are `Animated*` from the live value |
| Interruptible, animate from presentation value | `Animated*` widgets re-target from current value; sheets/transitions use controllers that reset from current positions |
| Continuous feedback during gesture | Sliders update 1:1; `OneUiActionBar` pills press immediately |
| Momentum projection | Flutter's scrollable/sheet drag systems already project release velocity natively |
| 1:1 drag with grab offset | Bottom sheets/native drags track the finger offset |
| Spatial consistency | Page transitions: incoming page glides up while outgoing settles; sheet dismiss mirrors entry path |
| Rubber-band at boundaries | Native scroll physics; sliders clamp at ends |
| Velocity seam between drag & settle | Springs carry release velocity through `AnimationController.animateWith`/`SpringSimulation` re-targets |
| Translucent layering | One UI surfaces are tonal (color), not glass; blur reserved for L3+ floating where it earns its place — never stacked light-on-light |

## 4. Reduced motion

- `MediaQuery.disableAnimations` is read via `AppMotion.reducedMotion(context)`.
- `AppMotion.resolve(context, duration)` and `AppMotion.curveFor(context, curve)`
  collapse non-essential motion to instant/linear.
- Page transitions skip entirely when reduced motion is active.
- `OneUiHero`, `OneUiStatusPod`, `OneUiSurface`, `_PageHost`, audio/video/scanner
  control surfaces use resolved durations.
- Custom springs should be replaced by cross-fades or static transitions under
- reduced motion (no slides/parallax). Future: also react to
  `disableAnimations` in external viewers.

## 5. Feedback taxonomy (feedback kinds)

- **Status** — ongoing: transfer progress bars (accent filled), upload status pod.
- **Completion** — SnackBar ("saved to"), success icon in transfers.
- **Warning** — amber server-restart toast, sync conflict banner (`warningFor` tint).
- **Error** — inline error states (`OneUiEmptyState`) + SnackBar with server text.
- Haptics/audio: only for causal, same-frame, meaningful events (not wired yet;
  a future enhancement).

## 6. Interaction checklist (what a reviewer checks)

- [ ] No idle looping animations or full-viewport movement.
- [ ] All interactive targets ≥ 48dp.
- [ ] Hidden (off-screen) exit path mirrors entry path.
- [ ] Press feedback is instant; drag feedback is continuous.
- [ ] Reduced-motion collapses motion to opacity/instant.
- [ ] No abrupt brightness jumps on theme switch (theme toggle is instant by design,
  back/foreground consistency kept).