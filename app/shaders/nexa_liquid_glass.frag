#version 460 core
#include <flutter/runtime_effect.glsl>

// Impeller supplies the backdrop input texture dimensions and sampler.
// They are deliberately NOT used as the glass card's shape dimensions.
uniform vec2 u_size;
uniform sampler2D u_texture_input;

// Glass geometry is measured from the render object's scene-space transform.
uniform vec2 u_card_origin;
uniform vec2 u_card_size;
uniform vec4 u_corner_radii; // top-left, top-right, bottom-right, bottom-left

uniform float u_refraction_height; // physical px
uniform float u_refraction_amount; // physical px; negative bends toward the inner rim
uniform float u_depth_effect;      // 0..1.5
uniform float u_chromatic;         // RGB dispersion strength

out vec4 fragColor;

float radiusAt(vec2 p) {
    if (p.x < 0.0) {
        return p.y < 0.0 ? u_corner_radii.x : u_corner_radii.w;
    }
    return p.y < 0.0 ? u_corner_radii.y : u_corner_radii.z;
}

float sdRoundedRect(vec2 p, vec2 halfSize, float radius) {
    vec2 q = abs(p) - (halfSize - vec2(radius));
    float outside = length(max(q, vec2(0.0))) - radius;
    float inside = min(max(q.x, q.y), 0.0);
    return outside + inside;
}

vec2 gradSdRoundedRect(vec2 p, vec2 halfSize, float radius) {
    vec2 q = abs(p) - (halfSize - vec2(radius));
    if (q.x >= 0.0 || q.y >= 0.0) {
        vec2 outward = sign(p) * normalize(max(q, vec2(0.0)));
        return length(outward) > 0.0001 ? outward : vec2(0.0, -1.0);
    }
    float gradX = step(q.y, q.x);
    return sign(p) * vec2(gradX, 1.0 - gradX);
}

// Kyant-style circular lens map: zero at the inner end of the shoulder,
// strongest right at the physical edge, with a smooth non-linear falloff.
float circleMap(float x) {
    float c = clamp(x, 0.0, 1.0);
    return 1.0 - sqrt(max(1.0 - c * c, 0.0));
}

vec2 sceneUv(vec2 scenePx) {
    vec2 uv = clamp(scenePx / u_size, vec2(0.001), vec2(0.999));
#if defined(IMPELLER_TARGET_OPENGLES) && !defined(IMPELLER_OPENGLES_UNFLIPPED_DEPRECATED)
    uv.y = 1.0 - uv.y;
#endif
    return uv;
}

vec4 sampleBackdrop(vec2 scenePx) {
    return texture(u_texture_input, sceneUv(scenePx));
}

void main() {
    // FlutterFragCoord is in the same scene-space physical pixel domain as
    // u_card_origin. The input texture may be larger than the glass surface.
    vec2 scenePx = FlutterFragCoord().xy;
    vec2 localPx = scenePx - u_card_origin;
    vec2 halfSize = u_card_size * 0.5;
    vec2 centered = localPx - halfSize;
    float radius = clamp(radiusAt(centered), 0.0, min(halfSize.x, halfSize.y));
    float sd = sdRoundedRect(centered, halfSize, radius);

    // The shape edge is anti-aliased at the actual SDF boundary.
    float coverage = 1.0 - smoothstep(-0.5, 0.5, sd);
    if (sd > 0.5) {
        fragColor = vec4(0.0);
        return;
    }

    vec4 base = sampleBackdrop(scenePx);
    vec3 color = base.rgb;
    float alpha = base.a;
    float inset = max(-sd, 0.0);

    // Bend scene pixels only in the curved rim/shoulder. This means every
    // instance (bottom dock, More panel, action sheet) refracts at its own
    // rounded rectangle instead of around the entire backdrop texture.
    if (u_refraction_height > 0.5 && inset < u_refraction_height) {
        float lens = circleMap(1.0 - inset / u_refraction_height);
        float displacement = lens * u_refraction_amount;
        vec2 normal = gradSdRoundedRect(centered, halfSize, radius);
        vec2 radial = length(centered) > 0.001
            ? normalize(centered) : vec2(0.0);
        vec2 bendNormal = normalize(normal + radial * u_depth_effect + vec2(0.00001));
        vec2 refractedPx = scenePx + bendNormal * displacement;

        // Keep chromatic separation subtle and local to the rounded corners.
        // The three wavelength paths are premultiplied-alpha safe.
        float cornerFactor = clamp(
            abs((centered.x / max(halfSize.x, 1.0)) *
                (centered.y / max(halfSize.y, 1.0))),
            0.0, 1.0
        );
        vec2 dispersion = bendNormal * (u_chromatic * 2.2 * cornerFactor);
        vec4 redSample = sampleBackdrop(refractedPx + dispersion);
        vec4 greenSample = sampleBackdrop(refractedPx);
        vec4 blueSample = sampleBackdrop(refractedPx - dispersion);

        color = vec3(redSample.r, greenSample.g, blueSample.b);
        alpha = (redSample.a + greenSample.a + blueSample.a) / 3.0;
    }

    // A narrow Fresnel-like inner rim catches light, making the bevel legible
    // even when the scene behind the glass is mostly black.
    float rim = exp(-pow((inset - 1.0) / 1.65, 2.0));
    float innerRim = exp(-pow((inset - 7.0) / 5.0, 2.0));
    float shoulder = exp(-pow((inset - 20.0) / 12.0, 2.0));
    color += vec3(1.0) * (rim * 0.075 + innerRim * 0.020 + shoulder * 0.007);
    color += vec3(0.66, 0.79, 1.0) * pow(clamp(1.0 - inset /
        max(u_refraction_height, 1.0), 0.0, 1.0), 1.45) * 0.014;

    // ImageFilter shader input is premultiplied. Keep RGB within alpha so the
    // filtered glass remains correct at its anti-aliased boundary.
    fragColor = vec4(clamp(color, vec3(0.0), vec3(alpha)), alpha) * coverage;
}
