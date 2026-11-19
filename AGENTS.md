# NexaDrive engineering rules

## Design review

NexaDrive uses **Material 3 (Material You)** as its single design language. The
authoritative references are Google's published Material 3 guidance for color
(tonal palettes and roles), typography, shape, elevation, motion, components and
accessibility. Use the accessibility and craft review discipline from:

https://github.com/dickwu/apple-design-skill

but do **not** apply its Apple platform conventions, iOS chrome, or Liquid
Glass material rules. No custom implementation may claim to be Apple's native
material.

One design system is authoritative: the `App*` design tokens in
`app/lib/core/design/` plus the `Nexa*` component library in
`app/lib/ui/widgets/`. These implement Material 3 roles and components. Do not
add a parallel design system, and do not declare per-screen styling that
bypasses these tokens. The floating pill navigation is a deliberate NexaDrive
signature; keep it, but express it with Material 3 surfaces, shape and motion.

## Product rules

- The server owns authorization. Never trust the client for permissions.
- Never build filesystem paths by concatenating untrusted strings without validation.
- Store actual user files as normal filesystem files.
- Passwords must never be stored in plaintext.
- Session tokens must not be stored in plaintext in SQLite.
- Prefer Tailscale Serve in front of the local Axum server; the embedded SQLite database never listens on the network.
- Do not use Tailscale Funnel for the default private deployment.
- Keep mobile and desktop clients on the same Flutter codebase.