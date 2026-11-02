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

  vec2 pixel = FlutterFragCoord().xy;
  vec2 halfSize = u_size * 0.5;
  float radius = min(halfSize.x, halfSize.y);
  vec2 local = pixel - halfSize;
  vec2 q = abs(local) - vec2(halfSize.x - radius, 0.0);
  float signedDistance =
      length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
  float insideDistance = max(-signedDistance, 0.0);

  // A broad optical rim bends the page image before the light catches its edge.
  float rim = 1.0 - smoothstep(0.0, max(7.0, radius * 0.28), insideDistance);
  float edgeLine = exp(-pow((insideDistance - 1.15) / 1.6, 2.0));
  float innerGlow = exp(-pow((insideDistance - 5.0) / 3.2, 2.0));

  vec2 normalVector = vec2(
      sign(local.x) * max(abs(local.x) - (halfSize.x - radius), 0.0),
      local.y
  );
  vec2 normal = normalize(normalVector + vec2(0.0001, 0.0001));
  vec2 bend = normal * rim * (13.0 / u_size);

  // Slightly separated colour channels create the glass edge's prismatic fringe.
  vec3 refracted;
  refracted.r = texture(u_texture, uv + bend * 1.16).r;
  refracted.g = texture(u_texture, uv + bend).g;
  refracted.b = texture(u_texture, uv + bend * 0.84).b;

  vec2 texel = 1.8 / u_size;
  vec3 centre = texture(u_texture, uv).rgb;
  vec3 diffusion =
      centre * 0.48 +
      texture(u_texture, uv + vec2(texel.x, 0.0)).rgb * 0.13 +
      texture(u_texture, uv - vec2(texel.x, 0.0)).rgb * 0.13 +
      texture(u_texture, uv + vec2(0.0, texel.y)).rgb * 0.13 +
      texture(u_texture, uv - vec2(0.0, texel.y)).rgb * 0.13;
  vec3 optical = mix(diffusion, refracted, 0.66);

  // Lift colour separation gently instead of flattening the live backdrop.
  float luminance = dot(optical, vec3(0.2126, 0.7152, 0.0722));
  optical = mix(vec3(luminance), optical, 1.24);
  optical = (optical - 0.5) * 1.035 + 0.5;

  // Soft diagonal specular reflection and an iris-to-cyan edge sheen.
  float diagonal = uv.y - (0.10 + uv.x * 0.12);
  float specular = exp(-pow(diagonal / 0.105, 2.0)) *
      smoothstep(0.04, 0.24, uv.x) * 0.075;
  vec3 spectral = mix(vec3(0.34, 0.76, 0.96),
                      vec3(0.72, 0.58, 1.0), smoothstep(0.04, 0.96, uv.x));
  optical += spectral * (innerGlow * 0.075 + edgeLine * 0.12);
  optical += vec3(1.0) * (edgeLine * 0.17 + specular);
  optical += vec3(0.12, 0.18, 0.34) * (rim * 0.025);

  fragColor = vec4(clamp(optical, 0.0, 1.0), 1.0);
}
