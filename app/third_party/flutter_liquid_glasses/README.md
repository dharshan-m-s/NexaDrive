# Liquid glass rendering reference

This directory records the third-party source used by NexaDrive's optical-glass renderer.

- Upstream project: https://github.com/losewayy/flutter_liquid_glasses
- Upstream version: 0.1.3
- Pinned source commit: f67b4615fcd6a47d2ffde15246b8888f8383446e
- License: Apache-2.0 (see LICENSE and NOTICE)

NexaDrive vendors the reference shader, highlight shader, parameter binding,
backdrop surface and foreground painter under `lib/ui/widgets/glass_engine`.
The NexaDrive-facing wrapper and visual tokens remain app-owned. The optics are
credited to Kyant's AndroidLiquidGlass implementation in NOTICE.
