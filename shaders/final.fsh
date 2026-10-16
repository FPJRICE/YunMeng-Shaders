#version 330 compatibility
#include "/lib/camera_options.glsl"
#include "/lib/presentation.glsl"
noperspective in vec2 vTexCoord;
layout(location = 0) out vec4 outColor0;
#if ANTI_ALIASING > 0
uniform sampler2D colortex3;
vec3 preparedPixel(ivec2 p) {
    return texelFetch(colortex3, clamp(p, ivec2(0), textureSize(colortex3, 0) - 1), 0).rgb;
}
vec3 preparedLinear(vec2 pixel) {
    vec2 q = pixel - 0.5;
    ivec2 p = ivec2(floor(q));
    vec2 f = fract(q);
    return mix(mix(preparedPixel(p), preparedPixel(p + ivec2(1,0)), f.x),
               mix(preparedPixel(p + ivec2(0,1)), preparedPixel(p + ivec2(1,1)), f.x), f.y);
}
float aaLuma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
vec3 spatialAA(vec2 uv) {
    vec2 pixel = uv * vec2(textureSize(colortex3, 0));
    ivec2 p = ivec2(pixel);
    vec3 c = preparedPixel(p);
    float m = aaLuma(c);
    float n = aaLuma(preparedPixel(p + ivec2(0,1)));
    float s = aaLuma(preparedPixel(p - ivec2(0,1)));
    float e = aaLuma(preparedPixel(p + ivec2(1,0)));
    float w = aaLuma(preparedPixel(p - ivec2(1,0)));
    float lo = min(m,min(min(n,s),min(e,w)));
    float hi = max(m,max(max(n,s),max(e,w)));
    float contrast = hi-lo;
    if (contrast < max(0.025, hi * 0.10)) return c;
    vec2 gradient = vec2(e-w,n-s);
    float g = length(gradient);
    // No stable edge direction: preserve fine checks and isolated ink marks.
    if (g < contrast * 0.15) return c;
    vec2 tangent = vec2(-gradient.y,gradient.x) / g;
    float radius = (ANTI_ALIASING == 1) ? 0.75 : 1.25;
    vec3 filtered = (preparedLinear(pixel+tangent*radius) + preparedLinear(pixel-tangent*radius))*0.5;
    float fl = aaLuma(filtered);
    if (fl < lo || fl > hi) return c;
    // Guofeng retains more of the original fine brush/outline contrast.
    float blendWeight = (STYLE_SELECTION == 0) ? 0.55 : 0.70;
    return mix(c,filtered,blendWeight);
}
#endif
void main() {
#if ANTI_ALIASING > 0
    vec3 color = spatialAA(vTexCoord);
    if (STYLE_SELECTION == 0 && PAPER_GRAIN_STRENGTH > 0.0) {
        vec2 paperUV = vTexCoord;
        if (isEyeInWater == 1 && UNDERWATER_DISTORTION_STRENGTH > 0.0) {
            paperUV += vec2(sin(paperUV.y*14.0+frameTimeCounter*2.1),
                            cos(paperUV.x*12.0-frameTimeCounter*1.8)) * (0.0018*UNDERWATER_DISTORTION_STRENGTH);
            paperUV = clamp(paperUV,vec2(0.002),vec2(0.998));
        }
        color += vec3((valueNoise(paperUV*vec2(viewWidth,viewHeight)*0.22)-0.5)*0.012*PAPER_GRAIN_STRENGTH);
    }
#else
    vec3 color = preparePresentation(vTexCoord, true);
#endif
    outColor0 = vec4(applyPresentationBorder(color,vTexCoord),1.0);
}
