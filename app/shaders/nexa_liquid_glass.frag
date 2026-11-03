#version 460 core
#include <flutter/runtime_effect.glsl>

// ImageFilter.shader reserves float slots 0-1 for u_size and sampler slot 0
// for the filtered backdrop. Keep these uniforms first.
uniform vec2 u_size;
uniform vec4 u_corner_radii; // top-left, top-right, bottom-right, bottom-left
uniform sampler2D u_texture;
out vec4 fragColor;

float cornerRadius(vec2 local) {
  if (local.x < 0.0) {
    return local.y < 0.0 ? u_corner_radii.x : u_corner_radii.w;
  }
  return local.y < 0.0 ? u_corner_radii.y : u_corner_radii.z;
}

void main() {
  vec2 pixel = FlutterFragCoord().xy;
  vec2 uv = pixel / u_size;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif

  vec2 halfSize = u_size * 0.5;
  vec2 local = pixel - halfSize;
  float radius = clamp(cornerRadius(local), 0.0, min(halfSize.x, halfSize.y));
  vec2 corner = abs(local) - (halfSize - vec2(radius));
  float sd = length(max(corner, vec2(0.0))) +
      min(max(corner.x, corner.y), 0.0) - radius;
  float inset = max(-sd, 0.0);

  // A broad optical shoulder makes the lens visible on real phone screens,
  // while the centre remains almost undistorted.
  float shoulderWidth = clamp(min(u_size.x, u_size.y) * 0.20, 24.0, 46.0);
  float edge = 1.0 - smoothstep(1.0, shoulderWidth, inset);
  float bulge = exp(-inset / (shoulderWidth * 1.25));
  float rim = exp(-pow((inset - 1.2) / 1.7, 2.0));
  float innerRim = exp(-pow((inset - 7.0) / 5.0, 2.0));
  float shoulderRim = exp(-pow((inset - 20.0) / 12.0, 2.0));

  // Surface normal of the rounded rectangle, including its curved corners.
  vec2 outside = max(corner, vec2(0.0));
  vec2 n;
  if (outside.x > 0.0 && outside.y > 0.0) {
    n = outside * sign(local);
  } else if (corner.x > corner.y) {
    n = vec2(sign(local.x), 0.0);
  } else {
    n = vec2(0.0, sign(local.y));
  }
  n = normalize(n + vec2(0.00001));

  // Refraction is strongest at the curved shoulder, with a gentle lens
  // magnification toward the centre. Values are in physical pixels.
  float ripple = sin(inset * 0.12 + uv.x * 5.0 - uv.y * 4.0) * 1.4;
  float displacementPx = edge * (24.0 + ripple) + bulge * 3.0;
  vec2 bend = n * displacementPx / u_size;
  vec2 dispersion = n * (edge * 1.15 / u_size);
  vec2 baseUv = clamp(uv, vec2(0.001), vec2(0.999));

  vec4 base = texture(u_texture, baseUv);
  vec4 red = texture(u_texture, clamp(baseUv + bend + dispersion, vec2(0.001), vec2(0.999)));
  vec4 green = texture(u_texture, clamp(baseUv + bend, vec2(0.001), vec2(0.999)));
  vec4 blue = texture(u_texture, clamp(baseUv + bend - dispersion, vec2(0.001), vec2(0.999)));

  // Filter input is premultiplied. Unpremultiply before optical channel mix.
  vec3 baseRgb = base.rgb / max(base.a, 0.0001);
  vec3 lensRgb = vec3(
    red.r / max(red.a, 0.0001),
    green.g / max(green.a, 0.0001),
    blue.b / max(blue.a, 0.0001)
  );
  float refract = clamp(edge * 0.92 + bulge * 0.08, 0.0, 0.96);
  vec3 color = mix(baseRgb, lensRgb, refract);

  // Directional studio reflection: a soft broad light plus a crisp curved
  // edge highlight. These are restrained neutral reflections, not neon paint.
  float upperSweep = exp(-pow((uv.y - (0.035 + uv.x * 0.055)) / 0.085, 2.0));
  float leftSweep = exp(-pow((uv.x - 0.025) / 0.11, 2.0)) *
      smoothstep(0.02, 0.35, uv.y);
  float fresnel = pow(edge, 1.45);
  float reflection = rim * 0.30 + innerRim * 0.095 +
      shoulderRim * 0.035 + upperSweep * 0.075 + leftSweep * 0.035;

  color += vec3(1.0) * reflection;
  color += vec3(0.66, 0.78, 1.0) * fresnel * 0.055;
  color += vec3(1.0) * rim * 0.11;

  fragColor = vec4(clamp(color, 0.0, 1.0) * base.a, base.a);
}
