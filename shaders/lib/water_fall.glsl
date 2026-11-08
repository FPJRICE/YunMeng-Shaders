#ifndef YUNMENG_WATER_FALL
#define YUNMENG_WATER_FALL

// Shared advected sheet detail. Cardinal fluid walls keep a fixed world axis;
// neither the shading normal nor the camera rotates the pattern coordinates.
vec3 waterFallAcross(vec3 normal) {
    vec2 h = normal.xz;
    float len = length(h);
    if (len > 0.25) {
        vec2 t = vec2(-h.y, h.x) / len;
        return vec3(t.x, 0.0, t.y);
    }
    return abs(normal.x) > abs(normal.z) ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
}

// Hash without Sine by David Hoskins (MIT; credited in THIRD_PARTY_NOTICES).
// Bound the cell first to retain fractional hash precision far from the origin.
float waterFallHash(vec2 cell) {
    vec3 p=fract(vec3(mod(cell,251.0).xyx)*0.1031);
    p+=dot(p,p.yzx+33.33);
    return fract((p.x+p.y)*p.z);
}

vec3 waterFallNoise(vec2 p) {
    vec2 cell=floor(p),f=fract(p);
    float a=waterFallHash(cell),b=waterFallHash(cell+vec2(1.0,0.0));
    float c=waterFallHash(cell+vec2(0.0,1.0)),d=waterFallHash(cell+vec2(1.0));
    vec2 u=f*f*f*(f*(f*6.0-15.0)+10.0);
    vec2 du=30.0*f*f*(f*(f-2.0)+1.0);
    float crossTerm=a-b-c+d;
    return vec3(du*vec2(b-a+crossTerm*u.y,c-a+crossTerm*u.x),
                a+(b-a)*u.x+(c-a)*u.y+crossTerm*u.x*u.y);
}

// XY is the analytic slope in across/up axes; Z is irregular aeration density.
// Two elongated scales travel downward together, with no periodic stripe mask.
vec3 waterFallField(vec3 worldPos,vec3 normal,float time) {
    vec2 p=vec2(dot(worldPos,waterFallAcross(normal)),worldPos.y+time*1.35);
    vec2 scaleA=vec2(2.7,0.85),scaleB=vec2(4.59,1.19);
    vec3 a=waterFallNoise(p*scaleA);
    vec3 b=waterFallNoise(p*scaleB+vec2(19.3,7.1));
    return vec3((a.xy*scaleA*0.7+b.xy*scaleB*0.3)*0.06,
                a.z*0.7+b.z*0.3);
}
#endif
