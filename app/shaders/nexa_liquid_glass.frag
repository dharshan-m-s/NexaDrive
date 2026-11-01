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

  // The dock behaves like a thin optical element: the edge bends the
  // backdrop slightly while the centre remains clear and colour-rich.
  vec2 fromCentre = uv - vec2(0.5);
  float edgeDistance = min(
    min(uv.x, 1.0 - uv.x),
    min(uv.y, 1.0 - uv.y)
  );
  float rim = 1.0 - smoothstep(0.015, 0.16, edgeDistance);
  vec2 direction = normalize(fromCentre + vec2(0.0001));
  vec2 displacement = direction * rim * 0.010;

  vec2 texel = 1.35 / u_size;
  vec3 centre = texture(u_texture, uv).rgb;
  vec3 refracted;
  refracted.r = texture(u_texture, uv + displacement * 1.10).r;
  refracted.g = texture(u_texture, uv + displacement).g;
  refracted.b = texture(u_texture, uv + displacement * 0.90).b;

  // A restrained optical softness keeps text and icons behind the glass
  // legible without turning the material into a frosted white panel.
  vec3 softened = (
    centre * 0.42 +
    texture(u_texture, uv + vec2(texel.x, 0.0)).rgb * 0.145 +
    texture(u_texture, uv - vec2(texel.x, 0.0)).rgb * 0.145 +
    texture(u_texture, uv + vec2(0.0, texel.y)).rgb * 0.145 +
    texture(u_texture, uv - vec2(0.0, texel.y)).rgb * 0.145
  );
  vec3 optical = mix(softened, refracted, 0.58);

  float luminance = dot(optical, vec3(0.2126, 0.7152, 0.0722));
  optical = mix(vec3(luminance), optical, 1.08);

  // Directional specular response and a fine Fresnel rim.
  float topSheen = pow(max(0.0, 1.0 - uv.y), 5.0) * 0.035;
  float fresnel = pow(rim, 2.2) * 0.105;
  optical = mix(optical, vec3(1.0), topSheen + fresnel);

  fragColor = vec4(clamp(optical, 0.0, 1.0), 1.0);
}
