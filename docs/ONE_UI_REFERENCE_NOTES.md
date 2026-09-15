# Samsung One UI — Reference Notes for the NexaDrive Redesign

> Goal of this file: give the future spec author a documented, factually-sourced
> picture of Samsung's One UI (the visual language NexaDrive already mimics) plus the
> Apple Design methodology we use ONLY as a review lens (AGENTS.md: interaction quality
> and accessibility — NOT the Apple visual style).
>
> Naming convention used throughout the docs: **"SAMSUNG VISUAL LANGUAGE"** (what the
> UI must look/move like) vs **"APPLE METHODOLOGY"** (the evaluation grid we run every
> change through). The two are deliberately separate.

---

## 1. What One UI is (official framing)

- Samsung's Android UX for phones, tablets, wearables and DeX, oriented around
  **one-handed reachability**: interactive elements gravitate to the lower reachable
  zone, status/informational content sits in the upper viewable zone
  ("content near the top, controls near the reach-thumb area").
  Sources: Samsung Design One UI guide
  `design.samsung.com/global/contents/one-ui-7/index.html`; One UI 7 announcement
  `news.samsung.com`; product pages `samsung.com/us/apps/one-ui/` (One UI 9).
- Design pillars repeated across Samsung materials: **clear hierarchy, whitespace /
  visual breathing room, meaningful but restrained motion, large legible type,
  consistent roundness, high-contrast light/dark, honest materials** (layers that
  look physical in lighting/shadow), and **scalability across form factors**.

## 2. Version timeline (what changed) — v2 (Feb 2025) → v8.5 → v9

| Version | Key design facts (sourced) | Source |
|---------|----------------------------|--------|
| **One UI 7** (Android 15) | Full vision reboot: Now Bar (live mini-apps at the lock screen bottom), redesigned Quick Settings (blurred "All notifications" + circular tiles), Home screen with bigger, rounder icons/folders, smoother and more "juicy" animations, richer glass (in/out effects), redesigned Clock app. Base visual language NexaDrive already echoes (rounded tiles, glass, pill buttons). | design.samsung.com/…/one-ui-7; androidcentral.com/samsung-one-ui-7-review; androidpolice.com/one-ui-7/; androidauthority.com; 9to5google.com |
| **One UI 8 / 8.5** | 8.5 = the MAJOR visual overhaul refiner: much larger rounded widgets, wider cards, heavier use of blur/glass (Now settings pages), thicker spacing; 8.x tuned the One UI 7 base rather than redoing it. | sammobile.com/news/look-one-ui-9-design-changes-new-features/ (says little new vs 8.5) |
| **One UI 9** (Android 17, introduced with Z Fold8/flip8, then S26) | **Refinement, not repaint**: focus on *fluidity* (beta-pushed animation/transition smoothing, One UI Home 18 launcher), customizable Quick Panel (resize brightness/volume sliders, separate toggles from sliders), thicker sliders, circular media controls + wave animations on lock media player, "glassy" effects expanding, elastic search-bar expansions, compact About screen, new accessibility options, three-way split view for foldables. | sammobile.com/news/samsung-one-ui-9-everything-to-know/; sammobile.com/news/look-one-ui-9-design-changes-new-features/; androidheadlines.com (April 2026 leak roundup); sammyguru.com/galaxy-s26-stable-one-ui-9-fluidity/; geeky-gadgets.com/samsung-one-ui-9-vs-8-5/; samsung.com/us/apps/one-ui/ |

**Bottom line for NexaDrive:** One UI 9 = One UI 7's shapes + 8.5's amplitude +
a hard push on *smoothness*. So a faithful "One UI-inspired" spec should keep:
round-capped layers, one-primary-color hook with tonal containers, pill buttons and
segments, glass/backdrop surfaces, reachability layout, and now — per 9 — *tuned
springs and elastic feedback* on top of the existing money animations.

## 3. One UI interaction & motion recipes we can document as ground truth

(Facts as Samsung ships them; Flutter-equivalent notes in brackets.)

1. **`now bar` / "at a glance" floating pod** — key info pinned in a reachable,
   elevated pill (media, timers, downloads). NexaDrive analog today: upload dialog
   stays on screen with a live progress pill; Home has a pending card.
2. **Quick-Panel style adaptive controls** — sliders/toggles resize and split;
   customization is a headline. NexaDrive analog: Quick actions grid is fixed 2/4;
   a One UI 9 move = allow resizing row heights.
3. **Smoothness = first-class feature (One UI 9)** — even if unrelated to our scope,
   it licenses the "sources all animation from AppMotion" refactor.
4. **Glass layers with edge separation** — real blur behind floating pills/bars,
   bright edge highlight. NexaDrive already has a 6%-white sigma-12 blur bar in the
   photo viewer; the home/top bars are opaque — a documented gap vs the language.
5. **Tonal "container" system** — selected state = accent-on-accent-container; the
   same pairing NexaDrive's segmented controls + nav labels use (see DESIGN_TOKENS §1).

## 4. APPLE METHODOLOGY — the review lens (this is the apple-design skill)

Samsung defines *how it looks*; Apple's *Designing Fluid Interfaces* (WWDC 2018)
class + *Principles of Great Design* (WWDC 2026) define *how to know if it feels
right*. We borrow ONLY the method, never the visuals:

1. **Response** — feedback on press-down; audit every debounce/latency in the input
   path. NexaDrive: Material handles this; scroll-photo-tap already instant.
2. **Direct manipulation (1:1 tracking)** — dragged content stays glued to the
   finger/pointer; respect grab offset. NexaDrive: InteractiveViewer drags 1:1.
3. **Interruptibility (most important)** — every animation must be grab-able and
   reversible mid-flight, started from the live on-screen value, never a target
   value; never lock input during transitions; blend velocity on reversal.
   NexaDrive gap: sheet/dialog entrances & page fade are fixed-duration codecs; a
   user pull during the fade isn't redirected.
4. **Velocity handoff** — a gesture's release velocity feeds the spring (no seam).
   NexaDrive: none (no spring-based sheets yet).
5. **Momentum projection** — flick → project rest position → snap to nearest target
   at the projected point. NexaDrive: none; viewer uses fixed PageViewController.
6. **Spatial consistency** — things leave the way they came, originate from the
   trigger. NexaDrive: dialogs are Material-centered fades; sheets `showDragHandle`
   top-slide — acceptable, but menu-sheets could scale from their trigger.
7. **Rubber-banding at boundaries** — soft resistance, progressive. NexaDrive:
   none (InteractiveViewer hard-clamps at edges; RefreshIndicator provides the only
   overscroll feedback).
8. **Materials & depth** — translucent functional layers, hierarchy by material
   weight; never stack translucent-on-translucent. NexaDrive photo bar = correct
   first example.
9. **Multimodal feedback** — cause→effect on the same frame, cause-obvious, earned.
   NexaDrive: none (no haptics/sound wired).
10. **Reduced motion / contrast / transparency** — replace, don't strip. NexaDrive:
    `AppMotion.resolve` exists but is unused (see ACCESSIBILITY_AUDIT §6).

> Apple *defaults* worth a deliberate note: critically-damped springs
> (damping 1.0, response 0.3–0.4 s), overshoot ONLY on momentum gestures
> (damping ~0.8), move/reposition 0.4, drawer/sheet 0.3. **This maps cleanly onto
> NexaDrive's existing AppMotion token set** (spring response 0.35 s, damping 1.0 is
> already the critical-damping default) — the tokens are Apple-compatible *already*;
> the AppMotion STANDARD curve in the codebase is a 3-tap patch of the same idea.

## 5. Localization of the two methodologies onto NexaDrive today

| Concern | SAMSUNG VISUAL LANGUAGE (source of truth for look) | APPLE METHODOLOGY (source of truth for feel) |
|---------|---------------------------------------------------|----------------------------------------------|
| Shape/tokens | DESIGN_TOKENS.md (One UI shapes: radiusTile 18, radiusCard 22, pill radii, 24/32 gutters) | n/a |
| Motion engines | AppMotion curves + SpringConfig (documented) | Interruptible + velocity-aware on EVERY animation |
| Surfaces/depth | accent-container pairings; sheet top-28; glass on photo bar | translucent layers that read as material; never translucent-on-translucent |
| Reachability | One UI: controls bottom, content top | 1:1 tracking + rubber-banding |
| A11y | One UI 9 adds accessibility options; keep ≥374dp targets per Samsung guidance | contrast ≥4.5 normal (see ACCESSIBILITY_AUDIT) + reduced-motion trinity |
| Performance | One UI 9 makes smoothness a feature | frame-level: transform/opacity only, no relayout per frame |

## 6. Guardrails for the future spec author (from these notes)

- NO Apple-specific visuals (SF/icons, Visual Design language, rounded-square icon
  grid/control-pad aesthetics). Keep One UI: softer pills, larger radius, brand-tint
  containers, cloud character, thicker whitespace.
- Keep the "one accent + tonal container" system; fix ONLY the contrast gaps
  documented in ACCESSIBILITY_AUDIT §1.
- Adopt AppMotion everywhere (single motion source), then optionally add: interruptible
  spring sheets, momentum on the Photo Viewer, rubber-band overscroll, and pick the
  pulsed "now-bar-upload" already in the app as the flagship One UI 9 gesture.
- Do not copy Samsung's proprietary assets; patterns only.
- Every change must still pass: `flutter analyze` clean, widget tests (17), 7-size
  integration sweep, and the 20 MB chunk upload SHA-256 round-trip test.