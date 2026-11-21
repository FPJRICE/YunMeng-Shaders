#ifndef YUNMENG_CLOUD_FIELD
#define YUNMENG_CLOUD_FIELD

#ifndef SKY_STYLE
#define SKY_STYLE 0                   // [0 1] 0: Wuxia Smooth, 1: Minecraft Voxel
#endif
#define CLOUD_SHAPE 0                 // [0 1 2 3] 0: Auto (By Sky Style), 1: Soft Volumetric, 2: Minecraft Voxel, 3: Tall Volumetric
#define ACTIVE_CLOUD_FORM ((CLOUD_SHAPE == 0) ? ((SKY_STYLE == 1) ? 2 : 1) : CLOUD_SHAPE)
#define CLOUD_COVERAGE 0.50           // [0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]
#define CLOUD_DENSITY 1.00            // [0.25 0.50 0.75 1.00 1.25 1.50 1.75 2.00]
#define CLOUD_ALTITUDE 184.0          // [128.0 144.0 160.0 176.0 184.0 200.0 216.0 236.0 256.0]
#define CLOUD_THICKNESS 64.0          // [28.0 36.0 48.0 56.0 64.0 76.0 92.0 112.0]
#define CLOUD_SCALE 1.00              // [0.50 0.75 1.00 1.25 1.50 1.75 2.00 2.50]
#define CLOUD_SPEED 1.00              // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00 3.00]
#define CLOUD_RENDER_DISTANCE 2400.0  // [1000.0 1400.0 1800.0 2200.0 2400.0 2800.0 3200.0]
#define CLOUD_RAIN_COVERAGE 0.78      // [0.55 0.65 0.72 0.78 0.85 0.92 1.00]
#define CLOUD_HORIZON_CURVE 0.065     // [0.000 0.030 0.050 0.065 0.080 0.100 0.120]

uniform sampler2D cloudVolumeTex;
uniform sampler2D cloudTex;

// Periodic 64^3 volume stored as 8x8 slices with one-texel gutters.
// Two bilinear fetches provide continuous trilinear interpolation in 3D.
vec4 cloudVolume(vec3 p) {
    vec3 q = fract(p) * 64.0;
    vec3 cell = floor(q);
    vec3 fraction = fract(q);
    fraction = fraction * fraction * (3.0 - 2.0 * fraction);
    q = cell + fraction;
    float layer = cell.y;
    float nextLayer = mod(layer + 1.0, 64.0);
    vec2 tile0 = vec2(mod(layer, 8.0), floor(layer / 8.0));
    vec2 tile1 = vec2(mod(nextLayer, 8.0), floor(nextLayer / 8.0));
    // Atlas rows are world X; columns are world Z.
    vec2 uv = q.zx + 1.5;
    return mix(textureLod(cloudVolumeTex, (tile0 * 66.0 + uv) / 528.0, 0.0),
               textureLod(cloudVolumeTex, (tile1 * 66.0 + uv) / 528.0, 0.0), fraction.y);
}

void cloudBounds(int mode, out float base, out float top) {
    base = CLOUD_ALTITUDE;
    if (ACTIVE_CLOUD_FORM == 2) {
        // Dual-layer Minecraft Voxel envelope:
        // - Lower Main Voxel Layer: [base, base + 4.6] (sleek 4.6-block 3D plates, never chunky!)
        // - Upper Translucent Voxel Layer: [base + 28.0, base + 32.2] (4.2-block high translucent veil)
        top = base + 32.2;
    } else {
        float shapeMult = (ACTIVE_CLOUD_FORM == 1) ? 1.0 : (mode == 1 ? 1.65 : 2.00);
        top = base + CLOUD_THICKNESS * shapeMult;
    }
}

vec2 cloudWind(float time) {
    return vec2(0.75, 0.28) * (time * CLOUD_SPEED);
}

// Evaluates quantized voxel cell occupancy using meso/detail channels so blocky islands form
// sleek 1..4 cell ribbons and puffs like Vanilla Minecraft rather than wide chunky continents.
float evalVoxelCellSignal(vec2 cellId, float cellSize, int mode) {
    vec2 wXZ = (cellId + 0.5) * cellSize;
    vec4 m1 = textureLod(cloudTex, fract(wXZ * 0.00145 + vec2(0.31, 0.57)), 0.0);
    vec4 m2 = textureLod(cloudTex, fract(wXZ * 0.00380 + vec2(0.67, 0.23)), 0.0);
    return (mode == 1)
        ? (m1.g * 0.38 + m2.b * 0.38 + m2.a * 0.24)
        : (m1.g * 0.40 + m2.b * 0.36 + m1.b * 0.24);
}

float cloudDensity(vec3 pos, float altitude, float time, int mode,
                   float rain, float storm, float footprint,
                   out float localHeight, out float detail) {
    float base, top;
    cloudBounds(mode, base, top);
    localHeight = (altitude - base) / max(top - base, 1.0);
    detail = 0.5;
    if (localHeight <= 0.0 || localHeight >= 1.0) return 0.0;

    float effScale = max(CLOUD_SCALE, 0.25);
    vec2 sXZ = (pos.xz - cloudWind(time)) / effScale;

    float rainTargetCov = clamp(max(CLOUD_COVERAGE, CLOUD_RAIN_COVERAGE) + storm * 0.07, 0.20, 0.98);
    float effCov        = mix(CLOUD_COVERAGE, rainTargetCov, rain);

    #if (CLOUD_SHAPE == 2) || (CLOUD_SHAPE == 0 && SKY_STYLE == 1)
    // Dual-Layer Minecraft Voxel:
    // - Lower Main Layer: [base, base + 4.6] (10x10 block cells, crisp ~86% opacity)
    // - Upper Translucent Layer: [base + 28.0, base + 32.2] (12x12 block cells, airy ~36% opacity)
    bool inLower = (altitude >= base && altitude <= base + 4.6);
    bool inUpper = (altitude >= base + 28.0 && altitude <= base + 32.2);
    if (!inLower && !inUpper) return 0.0;

    float subH = inLower
        ? clamp((altitude - base) / 4.6, 0.0, 1.0)
        : clamp((altitude - (base + 28.0)) / 4.2, 0.0, 1.0);
    localHeight = subH;

    float cellSize = inLower ? 10.0 : 12.0;
    vec2 layerXZ   = inLower
        ? sXZ
        : ((pos.xz - cloudWind(time) * 0.72) / effScale + vec2(240.0, -190.0));
    vec2 gridCoord = layerXZ / cellSize;
    vec2 cellId    = floor(gridCoord);
    vec2 cellFract = fract(gridCoord);

    float effThresh = (inLower ? 0.695 : 0.700) + (0.50 - effCov) * 0.36;
    float c0 = evalVoxelCellSignal(cellId, cellSize, mode);
    if (c0 <= effThresh) return 0.0;

    float nxDir = (cellFract.x > 0.5) ? 1.0 : -1.0;
    float nzDir = (cellFract.y > 0.5) ? 1.0 : -1.0;
    float dx    = (cellFract.x > 0.5) ? (1.0 - cellFract.x) : cellFract.x;
    float dz    = (cellFract.y > 0.5) ? (1.0 - cellFract.y) : cellFract.y;

    float cX = evalVoxelCellSignal(cellId + vec2(nxDir, 0.0), cellSize, mode);
    float cZ = evalVoxelCellSignal(cellId + vec2(0.0, nzDir), cellSize, mode);
    bool openX = (cX <= effThresh);
    bool openZ = (cZ <= effThresh);

    // Sub-voxel anti-aliasing ONLY on exposed outer edges
    float aa = clamp(footprint * 0.0022, 0.012, 0.050);
    float edgeAlphaX = openX ? clamp(dx / aa, 0.0, 1.0) : 1.0;
    float edgeAlphaZ = openZ ? clamp(dz / aa, 0.0, 1.0) : 1.0;
    float voxSolid   = min(edgeAlphaX, edgeAlphaZ);

    // Encode exposed vertical wall normal in detail (>0.50) vs seamless horizontal interior (0.25)
    float wallBand = 0.14;
    bool onWallX = openX && (dx < wallBand);
    bool onWallZ = openZ && (dz < wallBand);
    if (onWallX || onWallZ) {
        bool useX = onWallX && (!onWallZ || (dx < dz));
        detail = useX ? ((nxDir > 0.0) ? 0.62 : 0.72)
                      : ((nzDir > 0.0) ? 0.82 : 0.92);
    } else {
        detail = 0.25;
    }

    float layerDensity = inLower ? 4.2 : 1.35;
    return voxSolid * layerDensity * CLOUD_DENSITY * (1.0 + rain * 0.15 + storm * 0.20);
    #else
    // Soft Volumetric (0, Default) & Tall Volumetric (2):
    float hOff = localHeight - 0.35;
    vec2 r1 = mat2(0.80, -0.60, 0.60, 0.80) * sXZ;
    vec2 r2 = mat2(0.64,  0.77, -0.77, 0.64) * r1 + vec2( 36.0, -28.0) * hOff;
    vec2 r3 = mat2(0.91,  0.41, -0.41, 0.91) * sXZ + vec2(-48.0,  38.0) * hOff;
    vec2 r4 = mat2(0.86, -0.50,  0.50, 0.86) * r2 + vec2( 60.0,  52.0) * hOff;

    vec4 oct1 = textureLod(cloudTex, fract(r1 * 0.00052 + vec2(0.31, 0.57)), 0.0);
    vec4 oct2 = textureLod(cloudTex, fract(r2 * 0.00108 + vec2(0.67, 0.23)), 0.0);
    vec4 oct3 = textureLod(cloudTex, fract(r3 * 0.00225 + vec2(0.19, 0.81)), 0.0);
    vec4 oct4 = textureLod(cloudTex, fract(r4 * 0.00460 + vec2(0.43, 0.12)), 0.0);

    float scXZ = (ACTIVE_CLOUD_FORM == 1) ? 240.0 : ((mode == 1) ? 255.0 : 240.0);
    float scY  = (ACTIVE_CLOUD_FORM == 1) ? 135.0 : ((mode == 1) ? 170.0 : 190.0);
    vec3 volCoord = vec3(r1.x / scXZ, (altitude - base) / scY, r1.y / scXZ);
    vec4 shape = cloudVolume(volCoord);

    // 1. Clean Pink-Noise Perlin-Billow FBM Hierarchy (zero harsh cellular hole-punching!)
    float weather    = smoothstep(0.20, 0.78, oct1.r * 0.56 + oct2.r * 0.44);
    float baseFbm    = oct1.g * 0.30 + oct2.g * 0.34 + oct3.b * 0.22 + oct4.b * 0.14;
    float cloudField = baseFbm * (0.76 + 0.24 * weather) + (weather - 0.50) * 0.10;

    // 2. Companion Cumulus Puffs in Bay Margins
    float marginZone = smoothstep(0.24, 0.50, weather) * (1.0 - smoothstep(0.58, 0.82, weather));
    cloudField += smoothstep(0.55, 0.82, oct3.a * 0.60 + oct4.a * 0.40) * marginZone * 0.10;

    // 3. 3D Volumetric Billow Sculpting (Preserves 3D billowy depth in both Clear and Rain/Storm weather!)
    float billow3D        = shape.r * 0.56 + shape.g * 0.28 + shape.b * 0.16;
    float upperDomeSculpt = smoothstep(0.22, 0.85, localHeight) * ((1.0 - oct3.b) * 0.075 + (1.0 - shape.r) * 0.070);

    float formation = cloudField * 0.74 + billow3D * 0.26 - upperDomeSculpt;
    detail          = oct4.a * 0.45 + shape.g * 0.35 + shape.b * 0.20;

    // 4. Asymmetric 3D Cumulus Profile
    float botArch  = smoothstep(0.0, 0.18, localHeight);
    float topArch  = 1.0 - smoothstep(0.28, 1.0, localHeight);
    float vertArch = botArch * (0.30 + 0.70 * topArch);
    float heightPenalty = (1.0 - botArch) * 0.075 + smoothstep(0.20, 1.0, localHeight) * ((ACTIVE_CLOUD_FORM == 1) ? 0.145 : 0.165);

    // Rain & storms increase cloud body while preserving sculpted sun-break channels (25-32% sky openings)
    // so Wuxia Smooth clouds never turn into a sealed 100% blanket during rain and thunderstorms!
    float stormBreak = smoothstep(0.60, 0.82, oct2.g * 0.52 + oct3.b * 0.48) * rain * 0.068;
    float covShift   = (0.50 - effCov) * 0.21;
    float threshold  = 0.448 + covShift + heightPenalty + stormBreak;

    float filterDetail = 1.0 - smoothstep(14.0, 58.0, footprint);
    float wispErode    = mix(0.48, 1.0 - detail, filterDetail) * 0.052;
    float rawSignal    = formation - threshold - wispErode;

    // Gradual cotton density ramp so outer cloud margins stay airy and translucent
    float softBody = max(rawSignal, 0.0) * smoothstep(0.0, 0.14, rawSignal);
    return softBody * 5.2 * CLOUD_DENSITY * vertArch * (1.0 + rain * 0.15 + storm * 0.20);
    #endif
}

int cloudLightCacheResolution() {
#if CLOUD_QUALITY == 0
    return 128;
#elif CLOUD_QUALITY == 1
    return 192;
#elif CLOUD_QUALITY == 2
    return 256;
#else
    return 352;
#endif
}

vec2 cloudLightCacheOrigin(vec2 size, vec3 cam, vec3 lightDir) {
    float effY = max(lightDir.y, 0.08);
    vec2 center = cam.xz + lightDir.xz * ((64.0 - cam.y) / effY);
    vec2 texelWorld = vec2(2048.0) / size;
    return floor(center / texelWorld) * texelWorld - vec2(1024.0);
}

float cloudFarCacheWeight(vec3 lightDir) {
    return 1.0 - smoothstep(0.10, 0.18, lightDir.y);
}

vec2 cloudFarCacheOrigin(vec2 size, vec2 tileSize, vec3 cam, vec3 lightDir, float side) {
    vec2 direction = lightDir.xz / max(length(lightDir.xz), 0.001);
    vec2 texelWorld = vec2(2048.0) / size;
    vec2 offset = floor(direction * (1536.0 * cloudFarCacheWeight(lightDir)) / texelWorld + 0.5) * texelWorld;
    vec2 crop = floor((size - tileSize) * 0.5) * texelWorld;
    return cloudLightCacheOrigin(size, cam, lightDir) + offset * side + crop;
}

// Smooth, continuous cloud transmittance for ground shadows and water lighting:
// Uses continuous bilinear coordinates (never floor() voxel snapping) with a wide penumbra ramp
// so cloud shadows gliding across beaches, grass, and water never pop or flicker in 1-frame steps!
float evalContinuousCloudField(vec2 wXZ, int mode) {
    vec4 m1 = textureLod(cloudTex, fract(wXZ * 0.00145 + vec2(0.31, 0.57)), 0.0);
    vec4 m2 = textureLod(cloudTex, fract(wXZ * 0.00380 + vec2(0.67, 0.23)), 0.0);
    return (mode == 1)
        ? (m1.g * 0.38 + m2.b * 0.38 + m2.a * 0.24)
        : (m1.g * 0.40 + m2.b * 0.36 + m1.b * 0.24);
}

// Selective, soft crepuscular hole transmittance for volumetric light shafts:
// 1. Uses continuous feathered hole edges (no hard binary voxel wedges).
// 2. Gates beams by a low-frequency "major sun-break" pocket so only select, wider openings
//    cast atmospheric shafts rather than overwhelming the sky with rays from every tiny hole.
float cloudShaftHoleTransmittance(vec3 origin, vec3 lightDir, float time, int mode,
                                  float rain, float storm) {
    if (mode == 3) return mix(1.0, mix(0.72, 0.22, storm), rain);
    if (lightDir.y <= 0.02) return 0.0;
    float base, top;
    cloudBounds(mode, base, top);
    if (origin.y >= top) return 1.0;

    float effLightY = max(lightDir.y, 0.08);
    float effScale  = max(CLOUD_SCALE, 0.25);
    float rainTargetCov = clamp(max(CLOUD_COVERAGE, CLOUD_RAIN_COVERAGE) + storm * 0.07, 0.20, 0.98);
    float effCov = mix(CLOUD_COVERAGE, rainTargetCov, rain);

    float h1 = max(base + 2.3, origin.y);
    vec2 p1  = origin.xz + lightDir.xz * ((h1 - origin.y) / effLightY);
    vec2 w1  = (p1 - cloudWind(time)) / effScale;

    // Evenly distributed medium-scale sun-break selector (~160-block spacing) so shafts appear
    // evenly distributed across the sky without wide dead zones or clumping!
    float breakA = textureLod(cloudTex, fract(w1 * 0.00220 + vec2(0.19, 0.63)), 0.0).g;
    float breakB = textureLod(cloudTex, fract(w1 * 0.00410 + vec2(0.53, 0.27)), 0.0).b;
    float pocketGate = smoothstep(0.42, 0.66, breakA * 0.56 + breakB * 0.44);

    #if (CLOUD_SHAPE == 2) || (CLOUD_SHAPE == 0 && SKY_STYLE == 1)
    float threshLow = 0.695 + (0.50 - effCov) * 0.36;
    float threshUp  = 0.700 + (0.50 - effCov) * 0.36;

    float sigCont1 = evalContinuousCloudField(w1, mode);
    float sigVox1  = evalVoxelCellSignal(floor(w1 / 10.0), 10.0, mode);
    float sig1     = mix(sigCont1, sigVox1, 0.35);
    float open1    = 1.0 - smoothstep(threshLow - 0.055, threshLow + 0.025, sig1);

    float h2 = max(base + 30.1, origin.y);
    vec2 p2  = origin.xz + lightDir.xz * ((h2 - origin.y) / effLightY);
    vec2 w2  = ((p2 - cloudWind(time) * 0.72) / effScale) + vec2(240.0, -190.0);
    float sig2  = evalContinuousCloudField(w2, mode);
    float open2 = 1.0 - 0.50 * smoothstep(threshUp - 0.055, threshUp + 0.030, sig2);

    return (open1 * open1) * open2 * mix(0.45, 1.0, pocketGate);
    #else
    // Smooth, balanced 2-level opening evaluation for Wuxia Smooth (Soft Volumetric) clouds:
    // Every genuine cloud opening and thin bay margin casts a clean crepuscular shaft!
    float hLow  = max(base + (top - base) * 0.22, origin.y);
    float hHigh = max(base + (top - base) * 0.52, origin.y);
    vec3 posLow  = vec3(origin.x + lightDir.x * ((hLow  - origin.y) / effLightY), hLow,  origin.z + lightDir.z * ((hLow  - origin.y) / effLightY));
    vec3 posHigh = vec3(origin.x + lightDir.x * ((hHigh - origin.y) / effLightY), hHigh, origin.z + lightDir.z * ((hHigh - origin.y) / effLightY));
    float lh1, det1, lh2, det2;
    float densLow  = cloudDensity(posLow,  hLow,  time, mode, rain, storm, 20.0, lh1, det1);
    float densHigh = cloudDensity(posHigh, hHigh, time, mode, rain, storm, 26.0, lh2, det2);
    float tr = exp(-(densLow * 1.45 + densHigh * 0.85));
    float openHole = smoothstep(0.08, 0.78, tr);
    return openHole * mix(0.48, 1.0, pocketGate);
    #endif
}

float cloudOpticalDepth(vec3 origin, vec3 lightDir, float time, int mode,
                        float rain, float storm) {
    if (lightDir.y <= 0.01) return 32.0;
    float base, top;
    cloudBounds(mode, base, top);
    if (origin.y >= top) return 0.0;
    float effY = max(lightDir.y, 0.08);
    #if (CLOUD_SHAPE == 2) || (CLOUD_SHAPE == 0 && SKY_STYLE == 1)
    // Smooth continuous penumbra optical depth for ground shadows (zero 1-frame voxel popping!)
    float effScale = max(CLOUD_SCALE, 0.25);
    float rainTargetCov = clamp(max(CLOUD_COVERAGE, CLOUD_RAIN_COVERAGE) + storm * 0.07, 0.20, 0.98);
    float effCov = mix(CLOUD_COVERAGE, rainTargetCov, rain);
    float threshLow = 0.695 + (0.50 - effCov) * 0.36;
    float h1 = max(base + 2.3, origin.y);
    vec2 p1  = origin.xz + lightDir.xz * ((h1 - origin.y) / effY);
    vec2 w1  = (p1 - cloudWind(time)) / effScale;
    float sig1 = evalContinuousCloudField(w1, mode);
    float cloudCover = smoothstep(threshLow - 0.085, threshLow + 0.085, sig1);
    return cloudCover * mix(1.4, 2.6, rain);
    #else
    const int SAMPLES = 4;
    float start = max(base, origin.y);
    float stepHeight = (top - start) / float(SAMPLES);
    float odScale = stepHeight * (7.0 / max(top - base, 1.0)) / effY;
    float od = 0.0;
    for (int i = 0; i < SAMPLES; ++i) {
        float h = start + (float(i) + 0.5) * stepHeight;
        vec3 pos = vec3(origin.x + lightDir.x * ((h - origin.y) / effY), h, origin.z + lightDir.z * ((h - origin.y) / effY));
        float localHeight, detail;
        float density = cloudDensity(pos, h, time, mode, rain, storm, 35.0, localHeight, detail);
        od += density * odScale;
        if (od >= 12.0) break;
    }
    return min(od, 32.0);
    #endif
}

vec3 cloudColumnOpticalDepth(vec3 origin, vec3 lightDir, float time, int mode,
                             float rain, float storm) {
    float base, top;
    cloudBounds(mode, base, top);
    float shaftTrans = cloudShaftHoleTransmittance(vec3(origin.x, 64.0, origin.z), lightDir, time, mode, rain, storm);
    #if (CLOUD_SHAPE == 2) || (CLOUD_SHAPE == 0 && SKY_STYLE == 1)
    float odAll = cloudOpticalDepth(vec3(origin.x, base - 1.0, origin.z), lightDir, time, mode, rain, storm);
    return vec3(odAll, odAll * 0.45, shaftTrans);
    #else
#if CLOUD_QUALITY == 0
    const int SAMPLES = 6;
#elif CLOUD_QUALITY == 1
    const int SAMPLES = 8;
#elif CLOUD_QUALITY == 2
    const int SAMPLES = 12;
#else
    const int SAMPLES = 16;
#endif
    vec2 od = vec2(0.0);
    float stepHeight = (top - base) / float(SAMPLES);
    float invLightY = 1.0 / max(lightDir.y, 0.08);
    float odScale = stepHeight * (7.0 / max(top - base, 1.0)) * invLightY;
    for (int i = 0; i < SAMPLES; ++i) {
        float f = (float(i) + 0.5) / float(SAMPLES);
        float h = mix(base, top, f);
        vec3 pos = origin + lightDir * ((h - origin.y) * invLightY);
        float localHeight, detail;
        float density = cloudDensity(pos, h, time, mode, rain, storm, 28.0, localHeight, detail);
        float stepOD = density * odScale;
        od += stepOD * vec2(1.0, step(0.40, f));
        if (od.y >= 12.0) break;
    }
    od = min(od, vec2(32.0));
    return vec3(od.x, od.y, shaftTrans);
    #endif
}

#ifdef YUNMENG_CLOUD_LIGHT_CACHE
uniform sampler2D colortex10;
uniform sampler2D colortex11;

ivec2 cloudCacheViewportSize() {
    return max(ivec2(vec2(viewWidth, viewHeight) * 0.5), ivec2(1));
}

float sampleFarCloudCache(ivec2 size, ivec2 offset, vec2 pixel, float altitude, int mode,
                          out float confidence) {
    vec2 edge = min(pixel, vec2(size - 1) - pixel);
    confidence = smoothstep(0.0, 2.0, min(edge.x, edge.y));
    if (confidence <= 0.0) return 0.0;
    ivec2 p = ivec2(floor(pixel)); vec2 f = fract(pixel);
    vec4 a = texelFetch(colortex11, clamp(p, ivec2(0), size - 1) + offset, 0);
    vec4 b = texelFetch(colortex11, clamp(p + ivec2(1, 0), ivec2(0), size - 1) + offset, 0);
    vec4 c = texelFetch(colortex11, clamp(p + ivec2(0, 1), ivec2(0), size - 1) + offset, 0);
    vec4 d = texelFetch(colortex11, clamp(p + ivec2(1), ivec2(0), size - 1) + offset, 0);
    if (min(min(a.a, b.a), min(c.a, d.a)) < 0.5) {
        confidence = 0.0;
        return 0.0;
    }
    vec2 column = mix(mix(a.rg, b.rg, f.x), mix(c.rg, d.rg, f.x), f.y);
    float base, top; cloudBounds(mode, base, top);
    float height = clamp((altitude - base) / max(top - base, 1.0), 0.0, 1.0) * 2.0;
    return height < 1.0 ? mix(column.r, column.g, height) : mix(column.g, 0.0, height - 1.0);
}

// Fast hardware-cached crepuscular shaft transmittance lookup from colortex10.b (zero per-step cloud noise cost!)
float cachedCloudShaftTransmittance(vec3 origin, vec3 lightDir, float time, int mode,
                                    float rain, float storm) {
    if (mode == 3) return mix(1.0, mix(0.72, 0.22, storm), rain);
    if (lightDir.y <= 0.02) return 0.0;
    ivec2 size = min(min(textureSize(colortex10, 0), cloudCacheViewportSize()), ivec2(cloudLightCacheResolution()));
    vec2 mapOrigin = cloudLightCacheOrigin(vec2(size), cameraPosition, lightDir);
    float effY = max(lightDir.y, 0.08);
    vec2 reference = origin.xz + lightDir.xz * ((64.0 - origin.y) / effY);
    vec2 pixel = (reference - mapOrigin) / 2048.0 * vec2(size) - 0.5;
    vec2 edge = min(pixel, vec2(size - 1) - pixel);
    if (min(edge.x, edge.y) > 0.5) {
        ivec2 p = ivec2(floor(pixel));
        vec2 f = fract(pixel);
        float a = texelFetch(colortex10, clamp(p, ivec2(0), size - 1), 0).b;
        float b = texelFetch(colortex10, clamp(p + ivec2(1, 0), ivec2(0), size - 1), 0).b;
        float c = texelFetch(colortex10, clamp(p + ivec2(0, 1), ivec2(0), size - 1), 0).b;
        float d = texelFetch(colortex10, clamp(p + ivec2(1), ivec2(0), size - 1), 0).b;
        return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
    }
    return cloudShaftHoleTransmittance(origin, lightDir, time, mode, rain, storm);
}

float cachedCloudOpticalDepth(vec3 origin, vec3 lightDir, float time, int mode,
                              float rain, float storm) {
    float base, top;
    cloudBounds(mode, base, top);
    if (origin.y >= top) return 0.0;
    ivec2 size = min(min(textureSize(colortex10, 0), cloudCacheViewportSize()), ivec2(cloudLightCacheResolution()));
    vec2 mapOrigin = cloudLightCacheOrigin(vec2(size), cameraPosition, lightDir);
    float effY = max(lightDir.y, 0.08);
    vec2 reference = origin.xz + lightDir.xz * ((64.0 - origin.y) / effY);
    vec2 pixel = (reference - mapOrigin) / 2048.0 * vec2(size) - 0.5;
    vec2 edge = min(pixel, vec2(size - 1) - pixel);
    float confidence = smoothstep(0.0, 2.0, min(edge.x, edge.y));
    float nearOD = 0.0;
    if (confidence > 0.0) {
        ivec2 p = ivec2(floor(pixel)); vec2 f = fract(pixel);
        vec4 a = texelFetch(colortex10, clamp(p, ivec2(0), size - 1), 0);
        vec4 b = texelFetch(colortex10, clamp(p + ivec2(1, 0), ivec2(0), size - 1), 0);
        vec4 c = texelFetch(colortex10, clamp(p + ivec2(0, 1), ivec2(0), size - 1), 0);
        vec4 d = texelFetch(colortex10, clamp(p + ivec2(1), ivec2(0), size - 1), 0);
        if (min(min(a.a, b.a), min(c.a, d.a)) < 0.5) confidence = 0.0;
        else {
            vec2 column = mix(mix(a.rg, b.rg, f.x), mix(c.rg, d.rg, f.x), f.y);
            float height = clamp((origin.y - base) / max(top - base, 1.0), 0.0, 1.0) * 2.0;
            nearOD = height < 1.0 ? mix(column.r, column.g, height) : mix(column.g, 0.0, height - 1.0);
        }
    }
    if (confidence >= 1.0) return nearOD;

    float farWeight = cloudFarCacheWeight(lightDir);
    float farOD = 0.0;
    if (farWeight > 0.0) {
        ivec2 atlasSize = min(textureSize(colortex11, 0), cloudCacheViewportSize());
        ivec2 farSize = min(size, ivec2(atlasSize.x / 2, atlasSize.y));
        vec2 center = mapOrigin + 1024.0;
        float side = dot(reference - center, lightDir.xz) >= 0.0 ? 1.0 : -1.0;
        if (all(greaterThan(farSize, ivec2(0)))) {
            vec2 farOrigin = cloudFarCacheOrigin(vec2(size), vec2(farSize), cameraPosition, lightDir, side);
            vec2 farPixel = (reference - farOrigin) / 2048.0 * vec2(size) - 0.5;
            ivec2 offset = ivec2(side < 0.0 ? farSize.x : 0, 0);
            float farConfidence;
            farOD = sampleFarCloudCache(farSize, offset, farPixel, origin.y, mode, farConfidence);
            farWeight *= farConfidence;
        } else farWeight = 0.0;
    }
    if (farWeight < 1.0)
        farOD = mix(cloudOpticalDepth(origin, lightDir, time, mode, rain, storm), farOD, farWeight);
    return mix(farOD, nearOD, confidence);
}
#endif

float cloudLightTransmission(vec3 origin, vec3 lightDir, float time, int mode,
                             float rain, float storm) {
    if (mode == 3) return mix(1.0, mix(0.72, 0.22, storm), rain);
    if (lightDir.y <= 0.01) return 0.0;
#ifdef YUNMENG_CLOUD_LIGHT_CACHE
    return exp(-cachedCloudOpticalDepth(origin, lightDir, time, mode, rain, storm));
#else
    return exp(-cloudOpticalDepth(origin, lightDir, time, mode, rain, storm));
#endif
}
#endif
