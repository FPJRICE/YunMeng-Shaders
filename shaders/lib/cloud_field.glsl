#ifndef YUNMENG_CLOUD_FIELD
#define YUNMENG_CLOUD_FIELD
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
    base = 164.0;
    top = (mode == 1) ? 244.0 : 284.0;
}

vec2 cloudWind(float time) { return vec2(0.75, 0.28) * time; }

vec4 cloudOrganization(vec2 xz, float time, int mode) {
    vec2 p = xz - cloudWind(time);
    p = mat2(0.8, -0.6, 0.6, 0.8) * p;
    if (mode == 1) p *= vec2(0.76, 1.1);
    return textureLod(cloudTex, fract(p * 0.00048 + vec2(0.32, 0.68)), 0.0);
}

float cloudDensity(vec3 pos, float altitude, float time, int mode,
                   float rain, float storm, float footprint,
                   out float localHeight, out float detail) {
    float base, top;
    cloudBounds(mode, base, top);
    localHeight = (altitude-base)/(top-base);
    detail = 0.5;
    if (localHeight <= 0.0 || localHeight >= 1.0) return 0.0;
    vec4 organization = cloudOrganization(pos.xz, time, mode);
    float formationCoverage = organization.r * 0.8 + organization.g * 0.2;
    float weatherCoverage = smoothstep(0.30, 0.72, formationCoverage);
    // Give fair weather wider gaps between banks. Use the same density for
    // visible clouds, shadows, shafts and reflections; dense clouds still
    // obscure the sun. Keep the established rain ceiling at full wetness.
    float clearCoverage = (mode == 1)
        ? smoothstep(0.35, 0.76, formationCoverage)
        : smoothstep(0.38, 0.79, formationCoverage);
    float coverage = mix(clearCoverage, 0.86 + 0.14 * weatherCoverage, rain);
    // Vary crown heights per formation. Rain joins the banks into a deeper ceiling.
    float crown = mix(0.35, 1.0, smoothstep(0.25, 0.90, organization.g));
    crown = mix(crown, 0.76 + 0.24 * organization.g, rain);
    float localBase = base + organization.b * 10.0;
    localHeight = (altitude - localBase) / max((top - localBase) * crown, 1.0);
    if (localHeight <= 0.0 || localHeight >= 1.0 || coverage <= 0.0) return 0.0;
    vec3 p = pos - vec3(cloudWind(time).x, 0.0, cloudWind(time).y);
    p.y = altitude-localBase;
    p.xz += vec2(localHeight * 16.0, localHeight * -9.0);
    p /= (mode == 1) ? 300.0 : 250.0;
    if (mode == 1) p *= vec3(0.78, 1.15, 1.10);
    vec4 shape = cloudVolume(p);
    // Storm alpha has smooth, noncellular structure. Use the same density in
    // visible clouds, transmitted light and reflections, preserving clear RGB.
    float formation = mix(shape.r, shape.a, rain);
    detail = mix(shape.g, shape.a, rain * 0.65);
    float bottom = smoothstep(0.0, 0.09, localHeight);
    float topCut = smoothstep(0.48, 1.0, localHeight);
    float threshold = 0.58 - coverage * 0.18 + topCut * 0.13;
    // Subtractive erosion changes the silhouette, instead of just tinting a slab.
    float filterDetail = 1.0 - smoothstep(15.0, 55.0, footprint);
    float erosion = ((1.0-shape.g)*0.105 + (1.0-shape.b)*0.065) * filterDetail;
    // Fine edge breakup is local; distant formations keep their broad silhouette.
    if (footprint < 18.0) {
        vec4 edge = cloudVolume(p * 3.7 + vec3(0.17, 0.43, 0.29));
        erosion += (1.0 - edge.g) * 0.055 * (1.0 - smoothstep(6.0, 18.0, footprint));
    }
    // Coverage also fades density itself. A threshold-only coverage test can
    // discard an otherwise dense volume abruptly and expose a flat cut face.
    float coverageFade = smoothstep(0.0, 0.28, coverage);
    float body = max(formation - threshold - erosion, 0.0) * 5.5 * coverageFade;
    // The low storm deck is deliberately coherent, with 3D variation in its underside.
    float deck = max(formation - (0.31 + topCut * 0.34), 0.0) * rain * 2.4;
    return max(body, deck) * bottom * (1.0 - smoothstep(0.78, 1.0, localHeight))
           * (1.0 + storm * 0.4);
}

// Integrated extinction, shared by the world-aligned cache and its fallbacks.
int cloudLightCacheResolution() {
#if CLOUD_QUALITY == 0
    return 128;
#elif CLOUD_QUALITY == 1
    return 256;
#elif CLOUD_QUALITY == 2
    return 384;
#else
    return 512;
#endif
}

vec2 cloudLightCacheOrigin(vec2 size, vec3 cam, vec3 lightDir) {
    vec2 center = cam.xz + lightDir.xz * ((64.0-cam.y)/max(lightDir.y,0.01));
    vec2 texelWorld = vec2(2048.0)/size;
    return floor(center/texelWorld)*texelWorld - vec2(1024.0);
}

float cloudOpticalDepth(vec3 origin, vec3 lightDir, float time, int mode,
                        float rain, float storm) {
    if (lightDir.y <= 0.01) return 32.0;
    float base, top;
    cloudBounds(mode,base,top);
    if (origin.y >= top) return 0.0;
#if CLOUD_QUALITY == 0
    const int SAMPLES=12;
#elif CLOUD_QUALITY == 1
    const int SAMPLES=18;
#elif CLOUD_QUALITY == 2
    const int SAMPLES=32;
#else
    const int SAMPLES=48;
#endif
    float start=max(base,origin.y);
    float stepHeight=(top-start)/float(SAMPLES);
    float od=0.0;
    for (int i=0;i<SAMPLES;++i) {
        float h=start+(float(i)+0.5)*stepHeight;
        vec3 pos=origin+lightDir*((h-origin.y)/lightDir.y);
        float localHeight,detail;
        float density=cloudDensity(pos,h,time,mode,rain,storm,25.0,localHeight,detail);
        // Preserve full-column calibration, but scale the remaining path inside
        // clouds correctly and use the actual source elevation.
        od += density*stepHeight*(7.0/(top-base))/lightDir.y;
        if (od>=12.0) break;
    }
    return min(od,32.0);
}

// Remaining extinction at the base, one-third and two-thirds of the layer.
// One column integration supplies all three, avoiding per-fragment marching
// when a view ray or terrain enters the cloud layer.
vec3 cloudColumnOpticalDepth(vec3 origin, vec3 lightDir, float time, int mode,
                            float rain, float storm) {
    float base,top;
    cloudBounds(mode,base,top);
#if CLOUD_QUALITY == 0
    const int SAMPLES=12;
#elif CLOUD_QUALITY == 1
    const int SAMPLES=18;
#elif CLOUD_QUALITY == 2
    const int SAMPLES=32;
#else
    const int SAMPLES=48;
#endif
    vec3 od=vec3(0.0);
    float stepHeight=(top-base)/float(SAMPLES);
    for (int i=0;i<SAMPLES;++i) {
        float f=(float(i)+0.5)/float(SAMPLES);
        float h=mix(base,top,f);
        vec3 pos=origin+lightDir*((h-origin.y)/max(lightDir.y,0.01));
        float localHeight,detail;
        float density=cloudDensity(pos,h,time,mode,rain,storm,25.0,localHeight,detail);
        float stepOD=density*stepHeight*(7.0/(top-base))/max(lightDir.y,0.01);
        od+=stepOD*vec3(1.0,step(1.0/3.0,f),step(2.0/3.0,f));
    }
    return min(od,vec3(32.0));
}

#ifdef YUNMENG_CLOUD_LIGHT_CACHE
uniform sampler2D colortex10;
float cachedCloudOpticalDepth(vec3 origin, vec3 lightDir, float time, int mode,
                              float rain, float storm) {
    float base,top;
    cloudBounds(mode,base,top);
    if (origin.y>=top) return 0.0;
    ivec2 size=min(textureSize(colortex10,0),ivec2(cloudLightCacheResolution()));
    vec2 mapOrigin=cloudLightCacheOrigin(vec2(size),cameraPosition,lightDir);
    vec2 reference=origin.xz+lightDir.xz*((64.0-origin.y)/max(lightDir.y,0.01));
    vec2 pixel=(reference-mapOrigin)/2048.0*vec2(size)-0.5;
    vec2 edge=min(pixel,vec2(size-1)-pixel);
    float confidence=smoothstep(0.0,2.0,min(edge.x,edge.y));
    if (confidence<=0.0) return cloudOpticalDepth(origin,lightDir,time,mode,rain,storm);
    ivec2 p=ivec2(floor(pixel));vec2 f=fract(pixel);
    vec4 a=texelFetch(colortex10,clamp(p,ivec2(0),size-1),0);
    vec4 b=texelFetch(colortex10,clamp(p+ivec2(1,0),ivec2(0),size-1),0);
    vec4 c=texelFetch(colortex10,clamp(p+ivec2(0,1),ivec2(0),size-1),0);
    vec4 d=texelFetch(colortex10,clamp(p+ivec2(1),ivec2(0),size-1),0);
    if (min(min(a.a,b.a),min(c.a,d.a))<0.5)
        return cloudOpticalDepth(origin,lightDir,time,mode,rain,storm);
    vec3 column=mix(mix(a.rgb,b.rgb,f.x),mix(c.rgb,d.rgb,f.x),f.y);
    float height=clamp((origin.y-base)/(top-base),0.0,1.0)*3.0;
    float od=height<1.0 ? mix(column.r,column.g,height)
        : (height<2.0 ? mix(column.g,column.b,height-1.0)
                      : mix(column.b,0.0,height-2.0));
    if (confidence<1.0)
        od=mix(cloudOpticalDepth(origin,lightDir,time,mode,rain,storm),od,confidence);
    return od;
}
#endif

float cloudLightTransmission(vec3 origin, vec3 lightDir, float time, int mode,
                             float rain, float storm) {
    if (mode==3) return mix(1.0,mix(0.72,0.22,storm),rain);
    if (lightDir.y<=0.01) return 0.0;
#ifdef YUNMENG_CLOUD_LIGHT_CACHE
    return exp(-cachedCloudOpticalDepth(origin,lightDir,time,mode,rain,storm));
#else
    return exp(-cloudOpticalDepth(origin,lightDir,time,mode,rain,storm));
#endif
}
#endif
