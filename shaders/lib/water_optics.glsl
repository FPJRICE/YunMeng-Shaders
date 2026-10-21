#ifndef YUNMENG_WATER_OPTICS
#define YUNMENG_WATER_OPTICS
const float WATER_REFRACTIVE_INDEX=1.333;

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
