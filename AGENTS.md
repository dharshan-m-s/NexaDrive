# NexaDrive engineering rules

## Design review

Use the cross-platform design review methodology from:

https://github.com/dickwu/apple-design-skill

For UI work, consult the relevant rules for accessibility, color, typography, layout,
navigation, settings, search, loading and error states.

The visual language of NexaDrive is intentionally Apple/iOS-inspired (an iOS look and
feel, with a restrained approximation of Apple's Liquid Glass material system).
Use the skill for interaction quality and accessibility, and use Apple's own design
resources for discipline and hierarchy — without copying proprietary system assets
or claiming a custom implementation is Apple's native Liquid Glass.

One design system is authoritative: the `App*` design tokens in
`app/lib/core/design/` plus the `Nexa*` component library in
`app/lib/ui/widgets/`. Do not add a third parallel system, and do not
declare per-screen styling that bypasses these tokens.

## Product rules

- The server owns authorization. Never trust the client for permissions.
- Never build filesystem paths by concatenating untrusted strings without validation.
- Store actual user files as normal filesystem files.
- Passwords must never be stored in plaintext.
- Session tokens must not be stored in plaintext in SQLite.
- Prefer Tailscale Serve in front of the local Axum server; the embedded SQLite database never listens on the network.
- Do not use Tailscale Funnel for the default private deployment.
- Keep mobile and desktop clients on the same Flutter codebase.