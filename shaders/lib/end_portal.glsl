#ifndef YUNMENG_END_PORTAL
#define YUNMENG_END_PORTAL
#define END_PORTAL_LAYERS 3 // [2 3 4] Layered portal depth
uniform sampler2D portalInkTex;
uniform sampler2D portalCloudTex;

bool isYunMengEndPortal(float material) { return abs(material - 0.98) < 0.006; }

float portalHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 portalStars(vec2 plane, float worldFootprint) {
    // Rotated, gently warped cells with broad jitter and occasional gaps
    // conceal the construction grid. Seeds stay attached to drifting stars.
    const float spacing = 0.82;
    plane += frameTimeCounter * vec2(0.014, -0.006);
    plane = mat2(0.8572, -0.5150, 0.5150, 0.8572) * plane;
    plane.x += sin(plane.y * 0.65) * 0.16;
    vec2 cell = floor(plane / spacing);
    float seed = portalHash(cell);
    float variation = portalHash(cell + vec2(31.0, 73.0));
    vec2 location = vec2(0.12) + vec2(seed, variation) * 0.76;
    vec2 d = abs(fract(plane / spacing) - location) * spacing;
    float radius = max(mix(0.010, 0.048, variation * variation), worldFootprint * 0.70);
    float edge = max(worldFootprint * 0.65, 0.002);
    float core = 1.0 - smoothstep(radius - edge, radius + edge, max(d.x, d.y));
    float halo = exp(-dot(d, d) / (radius * radius * 7.0)) * 0.16;
    vec2 border = min(fract(plane / spacing), 1.0 - fract(plane / spacing)) * spacing;
    halo *= smoothstep(0.0, 0.08, min(border.x, border.y));
    // Independent gentle dim/bright cycles, never a synchronized flash or
    // a position-changing random seed. Roughly 4-8 seconds per cycle.
    float pulse = 0.5 + 0.5 * sin(frameTimeCounter * mix(0.8, 1.5, variation) + seed * 6.2831853);
    float twinkle = 0.22 + 0.78 * pulse * pulse;
    float distanceFade = 1.0 - smoothstep(0.10, 0.30, worldFootprint);
    vec3 tint = mix(vec3(0.80, 0.96, 0.87), vec3(1.0, 0.92, 0.65), step(0.60, seed));
    float visible = step(0.17, portalHash(cell + vec2(91.0, 17.0)));
    return tint * (core * 1.45 + halo) * twinkle * distanceFade * visible;
}

// Parallel planes behind the aperture: each ray intersects each layer at a
// different world position. A smooth grazing limit avoids horizon stretching.
vec3 renderYunMengEndPortal(vec3 playerPos, vec3 rayPlayer) {
    vec2 world = playerPos.xz + cameraPosition.xz;
    vec3 ray = normalize(rayPlayer);
    vec2 slope = ray.xz / sqrt(ray.y * ray.y + dot(ray.xz, ray.xz) * 0.065);
    vec3 color = STYLE_SELECTION == 0 ? vec3(0.016, 0.036, 0.023) : vec3(0.022, 0.052, 0.039);
    if (STYLE_SELECTION == 1) {
        float haze = 0.5 + 0.5 * sin(world.x * 0.43 + world.y * 0.31 + frameTimeCounter * 0.08)
            * sin(world.y * 0.57 - world.x * 0.19 - frameTimeCounter * 0.05);
        color += vec3(0.010, 0.020, 0.012) * haze;
    }
    vec3 starlight = vec3(0.0);
    for (int i = 0; i < END_PORTAL_LAYERS; i++) {
        float f = float(i) / float(END_PORTAL_LAYERS - 1);
        float layerDepth = mix(2.8, 0.30, f);
        float tileWidth = STYLE_SELECTION == 0 ? mix(3.4, 5.0, f) : mix(4.5, 6.5, f);
        vec2 uv = (world + slope * layerDepth) / tileWidth;
        uv += vec2(0.173, 0.317) * float(i);
        uv += frameTimeCounter * (STYLE_SELECTION == 0 ? vec2(0.0012, 0.0003) : vec2(0.0060, -0.0021)) * (0.55 + f * 0.45);
        // Quantize in the texture domain: stable voxel scale. An analytic
        // footprint also works in divergent SSR hit branches without derivatives.
        vec2 pixelUV = (floor(uv * 256.0) + 0.5) / 256.0;
        vec4 layer;
        if (STYLE_SELECTION == 0) layer = textureLod(portalInkTex, fract(pixelUV), 0.0);
        else layer = textureLod(portalCloudTex, fract(pixelUV), 0.0);
        float worldFootprint = max(length(playerPos), 0.01) * 1.2 / max(viewHeight, 1.0) / max(abs(ray.y), 0.10);
        float footprint = worldFootprint / tileWidth;
        float detail = 1.0 - smoothstep(0.012, 0.065, footprint);
        float opacity = layer.a * (STYLE_SELECTION == 0 ? mix(0.12, 0.78, f) : mix(0.22, 0.86, f)) * detail;
        vec3 tint = STYLE_SELECTION == 0 ? vec3(0.88, 0.98, 0.90) : vec3(0.78, 1.05, 1.16);
        vec3 lit = layer.rgb * tint * mix(0.35, 0.92, f);
        if (STYLE_SELECTION == 0) {
            // Tonal ink-wash strokes: muted jade shadows and pale celadon
            // highlights, preserving the artwork's stepped brush texture.
            float tone = dot(layer.rgb, vec3(0.25, 0.50, 0.25));
            lit = mix(vec3(0.07, 0.20, 0.12), vec3(0.68, 0.86, 0.65), tone)
                * tone * mix(0.40, 1.0, f);
        }
        if (STYLE_SELECTION == 1) {
            float tone = dot(layer.rgb, vec3(0.25, 0.50, 0.25));
            float crest = smoothstep(0.30, 0.70, tone);
            // Jade/celadon middles and warm pale crests echo the green frame.
            vec3 jade = vec3(max(layer.r, layer.g * 0.50), layer.g * 1.04,
                layer.b * 0.70 + layer.g * 0.18);
            lit = jade * mix(0.35, 0.92, f) * 1.12
                + vec3(0.16, 0.20, 0.08) * crest * mix(0.30, 0.80, f);
            float shadedFold = (1.0 - smoothstep(0.15, 0.40, tone)) * mix(0.70, 0.25, f);
            lit = mix(lit, vec3(0.020, 0.070, 0.050) * mix(0.55, 1.0, f), shadedFold);
        }
        color = mix(color, lit, opacity);

    }
    float starFootprint = max(length(playerPos), 0.01) * 1.2 / max(viewHeight, 1.0) / max(abs(ray.y), 0.10);
    starlight = portalStars(world + slope * 1.35, starFootprint);
    if (STYLE_SELECTION == 0) starlight *= vec3(0.88, 0.94, 0.78);
    // Stars occupy a separate luminous field so artwork layers cannot erase
    // them. Their own coordinate projections retain the parallax depths.
    return max(color + starlight, vec3(0.0));
}
#endif
