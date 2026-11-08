#ifndef YUNMENG_AURORA_GLSL
#define YUNMENG_AURORA_GLSL

// Aurora layer above volumetric clouds (Y=296..556).
// Supports both smooth continuous silk-ribbon drapery (Guofeng Jade Silk & Xianxia Celestial)
// and classic 2D-DDA 16x16-block stepped voxel pillars (Minecraft Voxel).
const float AURORA_BASE_Y = (CLOUD_ALTITUDE + CLOUD_THICKNESS * 2.0 + 16.0 > 296.0)
    ? (CLOUD_ALTITUDE + CLOUD_THICKNESS * 2.0 + 16.0)
    : 296.0;
const float AURORA_TOP_Y  = AURORA_BASE_Y + 260.0;

float auroraBandIntegral(float y0, float dy, float span, float scale) {
    if (abs(dy) < 0.0001) return span * exp(-y0 / scale);
    return (exp(-y0 / scale) - exp(-(y0 + dy * span) / scale)) * (scale / dy);
}

vec3 renderWorldAurora(vec3 origin, vec3 ray, float time, int mode, float starVisibility, float maxDistance) {
    if (mode == 3 || starVisibility <= 0.001) return vec3(0.0);
    float wet, storm, flash;
    evaluateWeatherState(wet, storm, flash);
    float night = smoothstep(0.02, 0.16, vNightFactor) * vNightFactor
        * (1.0 - wet * 0.94) * (1.0 - storm * 0.95);
    if (night <= 0.0) return vec3(0.0);

    // Smooth horizon fade so the aurora never hits the horizon hard or clashes with distant mist
    float horizonFade = smoothstep(0.03, 0.24, ray.y);
    if (horizonFade <= 0.001) return vec3(0.0);

    // The sky pass supplies the per-pixel celestial mask.
    float moonClearance = starVisibility;
    if (moonClearance <= 0.001) return vec3(0.0);

    bool voxelMode = (SKY_STYLE == 1);
    bool ink = (mode == 2) || (mode == 0 && STYLE_SELECTION == 0);

    vec3 safeRay = mix(vec3(-1.0), vec3(1.0), step(vec3(0.0), ray)) * max(abs(ray), vec3(0.00001));
    vec3 invRay  = 1.0 / safeRay;
    float yA = (AURORA_BASE_Y - origin.y) * invRay.y;
    float yB = (AURORA_TOP_Y  - origin.y) * invRay.y;
    float start  = max(min(yA, yB), 0.0);
    float finish = min(max(yA, yB), min(maxDistance, 1152.0));
    if (finish <= start) return vec3(0.0);

    // Palette harmonized with the celadon-jade & cerulean-indigo Moon atlases and midnight skybox
    vec3 footCol  = ink ? vec3(0.22, 0.78, 0.62) : vec3(0.16, 0.82, 0.72);
    vec3 midCol   = ink ? vec3(0.18, 0.52, 0.66) : vec3(0.20, 0.54, 0.84);
    vec3 crownCol = ink ? vec3(0.36, 0.26, 0.64) : vec3(0.44, 0.24, 0.78);
    float coreW   = ink ? 24.0 : 22.0;
    float haloW   = ink ? 64.0 : 58.0;
    float drift   = time * 0.032;

    if (voxelMode) {
        // Minecraft Voxel Aurora: 2D DDA traversal across 16x16 world-block vertical pillars
        const float AURORA_CELL = 16.0;
        const int VOXEL_STEPS   = 32;
        const float BAND_PERIOD = 340.0;
        float highScale = ink ? 175.0 : 200.0;

        vec3 startPos = origin + ray * start;
        vec2 cell     = floor(startPos.xz / AURORA_CELL);
        vec2 stepDir  = sign(safeRay.xz);
        vec2 nextBoundary = (cell + step(vec2(0.0), safeRay.xz)) * AURORA_CELL;
        vec2 tMax     = start + (nextBoundary - startPos.xz) * invRay.xz;
        vec2 tDelta   = AURORA_CELL * abs(invRay.xz);

        float t0 = start;
        vec3 light = vec3(0.0);
        for (int i = 0; i < VOXEL_STEPS; ++i) {
            if (t0 >= finish) break;
            float t1 = min(min(tMax.x, tMax.y), finish);
            float span = t1 - t0;
            if (span > 0.001) {
                vec2 center = (cell + 0.5) * AURORA_CELL;
                vec2 q = vec2(center.x * 0.82 - center.y * 0.57,
                              center.x * 0.57 + center.y * 0.82);
                float warp = 118.0 * sin(q.x * 0.0044 + drift * 0.48 + 0.78 * sin(q.x * 0.0020 - drift * 0.26))
                           +  46.0 * cos(q.x * 0.0105 - drift * 0.70 + 0.62 * sin(q.y * 0.0042));
                float wCoord    = q.y - warp;
                float bandId    = floor((wCoord + 0.5 * BAND_PERIOD) / BAND_PERIOD);
                float bandShift = 30.0 * sin(bandId * 2.17 + q.x * 0.0030);
                float dBand     = abs((wCoord - bandId * BAND_PERIOD) - bandShift);

                float curtain = (1.0 - smoothstep(coreW * 0.35, haloW, dBand));
                if (curtain > 0.002) {
                    float flute1 = 0.5 + 0.5 * sin(q.x * 0.045 + time * 0.18 + bandId * 1.3);
                    float flute2 = 0.5 + 0.5 * cos(q.x * 0.095 - time * 0.22 + q.y * 0.014);
                    float pillar = mix(flute2, flute1, 0.62);
                    float pillarStep = floor(pillar * 5.0) / 5.0;
                    float fluteStrength = 0.36 + 0.78 * smoothstep(0.15, 0.85, pillarStep);

                    float skirtHash = 0.5 + 0.5 * sin(q.x * 0.022 + 1.3 * cos(q.y * 0.018));
                    float colBase   = AURORA_BASE_Y + floor(skirtHash * 4.0) * 7.0;
                    float colTop    = min(AURORA_TOP_Y, colBase + 165.0 + pillarStep * 75.0);

                    float yEntry = origin.y + ray.y * t0;
                    float yExit  = origin.y + ray.y * t1;
                    float segMinY = min(yEntry, yExit);
                    float segMaxY = max(yEntry, yExit);

                    if (segMaxY > colBase && segMinY < colTop) {
                        float tColA = (colBase - origin.y) * invRay.y;
                        float tColB = (colTop  - origin.y) * invRay.y;
                        float c0    = max(t0, min(tColA, tColB));
                        float c1    = min(t1, max(tColA, tColB));
                        float cSpan = max(c1 - c0, 0.0);
                        if (cSpan > 0.001) {
                            float h0       = max((origin.y + ray.y * c0) - colBase, 0.0);
                            float footI    = auroraBandIntegral(h0, ray.y, cSpan, 34.0);
                            float midI     = auroraBandIntegral(h0, ray.y, cSpan, 92.0);
                            float fullI    = auroraBandIntegral(h0, ray.y, cSpan, highScale);
                            float bodyBand = max(midI - footI * 0.50, 0.0);
                            float highBand = max(fullI - midI * 0.55, 0.0) * (0.68 + 0.58 * pillarStep);

                            float distanceFade = 1.0 - smoothstep(680.0, 1120.0, 0.5 * (c0 + c1));
                            float pulse        = 0.90 + 0.10 * sin(time * 0.16 + q.x * 0.012);
                            float strength     = curtain * fluteStrength * pulse * distanceFade;

                            float foldHue  = 0.5 + 0.5 * sin(q.x * 0.014 - drift * 0.55);
                            vec3 localFoot = mix(footCol, midCol, 0.28 * foldHue);

                            light += (localFoot * (footI    * 0.0078)
                                    + midCol    * (bodyBand * 0.0068)
                                    + crownCol  * (highBand * 0.0105)) * strength;
                        }
                    }
                }
            }
            vec2 mask = step(tMax.xy, tMax.yx);
            t0     = t1;
            tMax  += mask * tDelta;
            cell  += mask * stepDir;
        }
        return light * night * horizonFade * moonClearance * (ink ? 0.72 : 0.82);
    }

    // Smooth Silk-Ribbon Aurora (Xianxia Celestial & Guofeng Jade Silk)
    const int STEPS = 24;
    const float BAND_PERIOD = 340.0;
    float totalSpan = finish - start;
    float stepSpan  = totalSpan / float(STEPS);
    float dither    = hash12(gl_FragCoord.xy);

    vec3 light = vec3(0.0);
    for (int i = 0; i < STEPS; ++i) {
        float t0 = start + (float(i) + dither) * stepSpan;
        vec3 pos = origin + ray * t0;
        if (pos.y < AURORA_BASE_Y || pos.y > AURORA_TOP_Y) continue;

        vec2 q = vec2(pos.x * 0.82 - pos.z * 0.57,
                      pos.x * 0.57 + pos.z * 0.82);
        float warp = 118.0 * sin(q.x * 0.0044 + drift * 0.48 + 0.78 * sin(q.x * 0.0020 - drift * 0.26))
                   +  46.0 * cos(q.x * 0.0105 - drift * 0.70 + 0.62 * sin(q.y * 0.0042));
        float wCoord    = q.y - warp;
        float bandId    = floor((wCoord + 0.5 * BAND_PERIOD) / BAND_PERIOD);
        float bandShift = 30.0 * sin(bandId * 2.17 + q.x * 0.0030);
        float dBand     = abs((wCoord - bandId * BAND_PERIOD) - bandShift);

        float curtain = (1.0 - smoothstep(coreW * 0.35, haloW, dBand));
        if (curtain > 0.002) {
            float flute1 = 0.5 + 0.5 * sin(q.x * 0.042 + time * 0.18 + bandId * 1.3 + sin(q.x * 0.015 - time * 0.10) * 1.8);
            float flute2 = 0.5 + 0.5 * cos(q.x * 0.095 - time * 0.22 + q.y * 0.012);
            float pillar = mix(flute2, flute1, 0.65);
            float pillarRamp    = smoothstep(0.12, 0.88, pillar);
            float fluteStrength = 0.38 + 0.76 * pillarRamp;

            float skirtWave  = 0.5 + 0.5 * sin(q.x * 0.020 + 1.2 * cos(q.y * 0.015));
            float colBase    = AURORA_BASE_Y + skirtWave * 22.0;
            float effHeight  = (ink ? 175.0 : 205.0) + pillarRamp * 48.0;
            float h          = pos.y - colBase;

            if (h > 0.0 && h < effHeight) {
                float hNorm      = h / effHeight;
                float bottomSoft = smoothstep(0.0, 0.16, hNorm);
                float topFade    = pow(clamp(1.0 - hNorm, 0.0, 1.0), 1.85);
                float env        = bottomSoft * topFade;

                float wFoot  = exp(-pow((hNorm - 0.16) / 0.14, 2.0)) * env;
                float wMid   = exp(-pow((hNorm - 0.38) / 0.22, 2.0)) * env;
                float wCrown = exp(-pow((hNorm - 0.68) / 0.28, 2.0)) * env * (0.75 + 0.50 * pillarRamp);

                float distanceFade = 1.0 - smoothstep(680.0, 1120.0, t0);
                float pulse        = 0.90 + 0.10 * sin(time * 0.16 + q.x * 0.012);
                float strength     = curtain * fluteStrength * pulse * distanceFade * stepSpan;

                float foldHue  = 0.5 + 0.5 * sin(q.x * 0.014 - drift * 0.55);
                vec3 localFoot = mix(footCol, midCol, 0.28 * foldHue);

                light += (localFoot * (wFoot  * 0.0082)
                        + midCol    * (wMid   * 0.0068)
                        + crownCol  * (wCrown * 0.0095)) * strength;
            }
        }
    }
    return light * night * horizonFade * moonClearance * (ink ? 0.72 : 0.82);
}

vec3 renderNightYunMengAurora(vec3 ray, float time, int mode, float starVisibility) {
    return renderWorldAurora(cameraPosition, ray, time, mode, starVisibility, 1152.0);
}
vec3 renderNightYunMengAurora(vec3 ray, float time, int mode) {
    return renderNightYunMengAurora(ray, time, mode, 1.0);
}

#endif
