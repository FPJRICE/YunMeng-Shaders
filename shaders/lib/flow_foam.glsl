#ifndef YUNMENG_FLOW_FOAM
#define YUNMENG_FLOW_FOAM
#ifndef SKY_STYLE
#define SKY_STYLE 0
#endif
#ifndef WATER_STYLE
#define WATER_STYLE 0
#endif
#ifndef ACTIVE_WATER_STYLE
#define ACTIVE_WATER_STYLE ((WATER_STYLE == 0) ? ((SKY_STYLE == 1) ? 2 : 1) : WATER_STYLE)
#endif
#include "/lib/water_fall.glsl"
#include "/lib/flow_direction.glsl"

// Soft organic broken froth clusters for flowing water only.
vec2 flowLacePatch(vec2 p) {
    vec3 broadSample = waterFallNoise(p * 1.55);
    vec2 warp = broadSample.xy * 0.16 + vec2(broadSample.z - 0.5) * 0.28;

    vec3 midSample  = waterFallNoise((p + warp) * 3.25 + vec2(13.7, 29.3));
    vec3 fineSample = waterFallNoise((p - warp * 0.60) * 6.50 + vec2(41.2, 17.8));

    float ridgeA = 1.0 - abs(midSample.z * 2.0 - 1.0);
    float ridgeB = 1.0 - abs(fineSample.z * 2.0 - 1.0);
    float filigree = ridgeA * 0.62 + ridgeB * 0.38;

    float broken   = smoothstep(0.62, 0.93, filigree) * (0.55 + 0.45 * fineSample.z);
    float patchEnv = smoothstep(0.44, 0.78, broadSample.z * 0.65 + midSample.z * 0.35);
    return vec2(broken, patchEnv);
}

vec2 flowFoamDetail(vec3 world, vec2 direction, bool curtain, float time) {
    if (curtain) {
        // View-independent horizontal world coordinate along any X, Z, or diagonal vertical waterfall wall.
        // Never uses screen-space normal derivatives, so front-facing walls never stripe at any view angle.
        float acrossCoord = world.x + world.z * 0.87;
        vec2 p = vec2(acrossCoord * 1.45, (world.y + time * 0.72) * 0.58);
        return flowLacePatch(p);
    }
    // Two overlapping advection phases keep the offset bounded at turns.
    float phase = fract(time / 3.2);
    vec2 flowVec = (dot(direction, direction) > 0.25) ? direction : vec2(0.0);
    vec2 a = flowLacePatch(world.xz - flowVec * (phase * 0.75));
    vec2 b = flowLacePatch(world.xz - flowVec * (fract(phase + 0.5) * 0.75));
    return mix(a, b, abs(phase * 2.0 - 1.0));
}

// Local projected evidence in screen space for adjacent waterfall impact transitions.
bool flowFoamSample(vec3 probe, out vec3 point, out float fluid) {
    vec4 clip = gbufferProjection * gbufferModelView * vec4(probe, 1.0);
    point = probe;
    fluid = 0.0;
    if (clip.w <= 0.05) return false;
    ivec2 size = textureSize(depthtex0, 0);
    vec2 uv = clip.xy / clip.w * 0.5 + 0.5 + cameraJitter(frameCounter, vec2(size));
    if (any(lessThanEqual(uv, vec2(0.001))) || any(greaterThanEqual(uv, vec2(0.999)))) {
        fluid = -1.0;
        return true;
    }
    ivec2 q = clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1);
    vec4 tag = texelFetch(colortex1, q, 0);
    float depth = texelFetch(depthtex0, q, 0).r;
    if (abs(tag.a - 0.90) > 0.05 || depth >= 0.999999) return false;
    vec3 vp = reconstructViewPos((vec2(q) + 0.5) / vec2(size), depth);
    point = (gbufferModelViewInverse * vec4(vp, 1.0)).xyz;
    fluid = texelFetch(colortex2, q, 0).a;
    return distance(point, probe) < 0.36;
}

float flowingContactFoam(
    vec3 player,
    vec3 world,
    vec3 faceNormal,
    float fluid,
    float footprint,
    float nearbyChange,
    float storedDirection,
    float verticalDrop
) {
    // The final visibility multiplier is exactly zero in these cases.
    if (FLOW_FOAM_STRENGTH == 0.0 || footprint >= 0.65) return 0.0;

    // Strictly classify flowing water from G-buffer fluid geometry metadata (`colortex2.a`):
    // - `fluid == 0.0` is flat, level source water (oceans, lakes, rivers, source blocks).
    // - `curtain` (`fluid > 0.85`) is a vertical waterfall face.
    // - `slope` (`0.185 < fluid < 0.315`) is a tilted/sloped flowing water top.
    // - `thin` (`0.058 < fluid < 0.15`) is a shallow downstream run-out tip.
    bool curtain = fluid > 0.85;
    bool slope   = waterIsSlopedTop(fluid);
    bool thin    = waterIsThinFlowTop(fluid);

    // HARD GUARD: Flat level water (oceans, lakes, ponds, flat source blocks where fluid == 0.0)
    // NEVER generates surface foam unless it is directly at a waterfall/slope boundary (nearbyChange >= 0.08).
    if (!curtain && !slope && !thin && nearbyChange < 0.08) {
        return 0.0;
    }

    float surfaceWeight = waterFlowSurfaceWeight(fluid);
    vec2 direction = decodeWaterFlow(storedDirection);
    surfaceWeight *= step(0.5, dot(direction, direction));

    float contact = 0.0;
    if (curtain) {
        vec3 outward = vec3(faceNormal.x, 0.0, faceNormal.z);
        outward /= max(length(outward), 1e-6);
        if (dot(outward, player) > 0.0) outward = -outward;
        for (int i = 0; i < 2; ++i) {
            vec3 hit;
            float other;
            bool water = flowFoamSample(player + outward * 0.10 - vec3(0.0, i == 0 ? 0.14 : 0.28, 0.0), hit, other);
            if (water && other >= 0.0 && other < 0.35 && hit.y < player.y - 0.025 &&
                hit.y > player.y - 0.36 && distance(hit.xz, player.xz) < 0.28) {
                contact = max(contact, 1.0 - smoothstep(0.12, 0.36, player.y - hit.y));
            }
        }
        // Soft landing splash where a vertical waterfall curtain meets shallow ground or a receiving step
        float groundLanding = 1.0 - smoothstep(0.04, 0.28, verticalDrop);
        contact = max(contact, groundLanding * 0.65);
    } else if (nearbyChange >= 0.08) {
        int count = slope ? 8 : 4;
        for (int i = 0; i < count; ++i) {
            int axis = i % 4;
            vec3 probeDir = axis < 2 ? vec3(axis == 0 ? -1.0 : 1.0, 0.0, 0.0)
                                     : vec3(0.0, 0.0, axis == 2 ? -1.0 : 1.0);
            vec3 probe = player + probeDir * 0.12 + vec3(0.0, i >= 4 ? -0.16 : 0.16, 0.0);
            vec3 hit;
            float other;
            bool water = flowFoamSample(probe, hit, other);
            float dy = hit.y - player.y;
            bool nearbyFall = water && (other > 0.80 || waterIsSlopedTop(other)) && distance(hit.xz, player.xz) < 0.28;
            float confidence = (1.0 - smoothstep(0.10, 0.28, distance(hit.xz, player.xz)))
                             * (1.0 - smoothstep(0.20, 0.36, abs(dy)));
            if (nearbyFall && dy > 0.025 && dy < 0.36) {
                contact = max(contact, confidence);
            } else if (nearbyFall && slope && dy < -0.025 && dy > -0.36) {
                contact = max(contact, confidence * 0.55);
            }
        }
        if (contact == 0.0 && !slope && !thin) return 0.0;
    }

    float time = frameTimeCounter * WIND_SPEED;
    vec3 foamWorld = (ACTIVE_WATER_STYLE == 2) ? ((floor(world * 16.0) + 0.5) / 16.0) : world;
    vec2 detail = flowFoamDetail(foamWorld, direction, curtain, time);
    float broken   = detail.x;
    float patchEnv = detail.y;

    float foam = 0.0;
    if (curtain) {
        float sparse = smoothstep(0.48, 0.92, patchEnv);
        foam = broken * sparse * (STYLE_SELECTION == 0 ? 0.045 : 0.060);
        foam = max(foam, contact * broken * patchEnv * 0.26);
    } else if (slope) {
        // Consistent light froth across all sloped flowing faces + step contacts
        foam = broken * patchEnv * (0.28 + 0.72 * max(surfaceWeight, contact)) * (STYLE_SELECTION == 0 ? 0.14 : 0.18);
    } else {
        // Only at direct waterfall impact on a pool or at thin flowing water run-out tips
        foam = contact * broken * patchEnv * 0.24;
        foam = max(foam, broken * patchEnv * surfaceWeight * (STYLE_SELECTION == 0 ? 0.10 : 0.13));
    }

    if (ACTIVE_WATER_STYLE == 2) foam = floor(foam * 24.0 + 0.5) / 24.0;
    return clamp(foam * FLOW_FOAM_STRENGTH * (1.0 - smoothstep(0.12, 0.65, footprint)), 0.0, 0.36);
}
#endif
