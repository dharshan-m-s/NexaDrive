#version 460 core
#include <flutter/runtime_effect.glsl>

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

  // Rounded-rectangle distance field with the actual ClipRRect corner radii.
  vec2 corner = abs(local) - (halfSize - vec2(radius));
  float signedDistance =
      length(max(corner, vec2(0.0))) + min(max(corner.x, corner.y), 0.0) - radius;
  float insideDistance = max(-signedDistance, 0.0);

  // Tight optical rim; the centre of the glass remains crisp and legible.
  float edgeSpan = clamp(min(u_size.x, u_size.y) * 0.22, 8.0, 18.0);
  float edgeMask = 1.0 - smoothstep(0.0, edgeSpan, insideDistance);
  float rimLine = exp(-pow((insideDistance - 1.15) / 1.45, 2.0));
  float innerRim = exp(-pow((insideDistance - 5.2) / 3.1, 2.0));

  // Derive the normal from the nearest edge or rounded corner.
  vec2 outside = max(corner, vec2(0.0));
  vec2 normalVector;
  if (outside.x > 0.0 && outside.y > 0.0) {
    normalVector = outside * sign(local);
  } else if (corner.x > corner.y) {
    normalVector = vec2(sign(local.x), 0.0);
  } else {
    normalVector = vec2(0.0, sign(local.y));
  }
  vec2 normal = normalize(normalVector + vec2(0.0001, 0.0001));

  // Bend and disperse only the outer rim, preserving useful detail beneath it.
  vec2 bend = normal * edgeMask * (5.2 / u_size);
  vec2 dispersion = normal * edgeMask * (0.75 / u_size);
  vec4 source = texture(u_texture, uv);

  vec3 refracted;
  refracted.r = texture(u_texture, uv + bend + dispersion).r;
  refracted.g = texture(u_texture, uv + bend).g;
  refracted.b = texture(u_texture, uv + bend - dispersion).b;
  vec3 optical = mix(source.rgb, refracted, edgeMask * 0.76);

  float luminance = dot(optical, vec3(0.2126, 0.7152, 0.0722));
  optical = mix(vec3(luminance), optical, 1.08);

  // Subtle iris-to-cyan Fresnel response and directional specular reflection.
  vec3 spectral = mix(
      vec3(0.34, 0.76, 0.96),
      vec3(0.72, 0.58, 1.0),
      smoothstep(0.06, 0.94, uv.x));
  float diagonal = uv.y - (0.09 + uv.x * 0.12);
  float specular = exp(-pow(diagonal / 0.095, 2.0)) *
      smoothstep(0.05, 0.24, uv.x) * 0.042;

  optical += spectral * (innerRim * 0.045 + rimLine * 0.095);
  optical += vec3(1.0) * (rimLine * 0.13 + specular);
  optical += vec3(0.12, 0.18, 0.34) * (edgeMask * 0.018);

  fragColor = vec4(clamp(optical, 0.0, 1.0), source.a);
}
