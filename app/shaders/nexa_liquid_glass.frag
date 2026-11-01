#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 u_size;
uniform sampler2D u_texture;
out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / u_size;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif

  // Signed distance to a horizontal capsule (the dock's stadium silhouette).
  // Using the actual pixel aspect ratio keeps the rim round rather than
  // producing the rectangular white outline of a generic UV edge gradient.
  vec2 local = FlutterFragCoord().xy - u_size * 0.5;
  vec2 halfSize = u_size * 0.5;
  float radius = min(halfSize.x, halfSize.y);
  vec2 q = abs(local) - vec2(halfSize.x - radius, 0.0);
  float signedDistance =
      length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
  float insideDistance = max(-signedDistance, 0.0);
  float rim = 1.0 - smoothstep(0.0, radius * 0.22, insideDistance);
  float fresnel = pow(rim, 2.2);

  vec2 normalVector = vec2(
      sign(local.x) * max(abs(local.x) - (halfSize.x - radius), 0.0),
      local.y
  );
  vec2 normal = normalize(normalVector + vec2(0.0001));
  vec2 bend = normal * rim * (7.5 / u_size);

  vec2 texel = 1.35 / u_size;
  vec3 centre = texture(u_texture, uv).rgb;
  vec3 refracted;
  refracted.r = texture(u_texture, uv + bend * 1.10).r;
  refracted.g = texture(u_texture, uv + bend).g;
  refracted.b = texture(u_texture, uv + bend * 0.90).b;

  // Diffusion and refraction are layered over the live backdrop capture.
  vec3 diffusion =
      centre * 0.56 +
      texture(u_texture, uv + vec2(texel.x, 0.0)).rgb * 0.11 +
      texture(u_texture, uv - vec2(texel.x, 0.0)).rgb * 0.11 +
      texture(u_texture, uv + vec2(0.0, texel.y)).rgb * 0.11 +
      texture(u_texture, uv - vec2(0.0, texel.y)).rgb * 0.11;
  vec3 optical = mix(diffusion, refracted, 0.58);

  // Vibrancy is restrained so the material carries the page's colours
  // instead of washing them into a pale grey slab.
  float luminance = dot(optical, vec3(0.2126, 0.7152, 0.0722));
  optical = mix(vec3(luminance), optical, 1.18);

  float topSheen = pow(max(0.0, 1.0 - uv.y), 7.0) * 0.035;
  optical = mix(optical, vec3(1.0), fresnel * 0.12 + topSheen);
  fragColor = vec4(clamp(optical, 0.0, 1.0), 1.0);
}
