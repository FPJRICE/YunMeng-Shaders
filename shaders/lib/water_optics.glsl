#ifndef YUNMENG_WATER_OPTICS
#define YUNMENG_WATER_OPTICS
const float WATER_REFRACTIVE_INDEX=1.333;

// Above-water RGBA8 metadata: 0 = source top, thin tops use 0.0625..0.125,
// slopes use 0.20..0.25, and curtains retain 0.5..1. Surface-foam weight is continuous.
// Underwater orientation metadata keeps its existing independent meaning.
bool waterIsSlopedTop(float metadata) {
    return metadata>0.185 && metadata<0.315;
}

bool waterIsThinFlowTop(float metadata) {
    return metadata>0.058 && metadata<0.15;
}

float waterFlowSurfaceWeight(float metadata) {
    if(waterIsSlopedTop(metadata)) return clamp((0.25-metadata)/0.05,0.0,1.0);
    if(waterIsThinFlowTop(metadata)) return clamp((0.125-metadata)/0.0625,0.0,1.0);
    return 0.0;
}

bool waterIsFlowTip(float metadata) {
    return waterFlowSurfaceWeight(metadata)>0.001;
}

vec3 waterFacingNormal(vec3 incident, vec3 normal) {
    return dot(incident,normal)>0.0 ? -normal : normal;
}

float waterExitTransmission(vec3 incident, vec3 normal) {
    float ci=clamp(-dot(incident,waterFacingNormal(incident,normal)),0.0,1.0);
    float st2=WATER_REFRACTIVE_INDEX*WATER_REFRACTIVE_INDEX*(1.0-ci*ci);
    if (st2>=1.0) return 0.0;
    float ct=sqrt(max(1.0-st2,0.0));
    float rs=(WATER_REFRACTIVE_INDEX*ci-ct)/max(WATER_REFRACTIVE_INDEX*ci+ct,1e-5);
    float rp=(WATER_REFRACTIVE_INDEX*ct-ci)/max(WATER_REFRACTIVE_INDEX*ct+ci,1e-5);
    return 1.0-clamp((rs*rs+rp*rp)*0.5,0.0,1.0);
}
#endif
