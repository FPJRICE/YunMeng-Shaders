#ifndef YUNMENG_FLOW_DIRECTION
#define YUNMENG_FLOW_DIRECTION

// Above-water colortex2.b: 0..254 encode horizontal flow angle; 255 is unknown.
// Other materials and submerged water retain their existing AO value.
float encodeWaterFlow(vec3 positionDx, vec3 positionDy, vec2 uvDx, vec2 uvDy) {
    float determinant=uvDx.x*uvDy.y-uvDx.y*uvDy.x;
    if(abs(determinant)<1e-16) return 1.0;
    // Minecraft rotates the flowing sprite so increasing V follows the current.
    vec2 along=(positionDy.xz*uvDx.x-positionDx.xz*uvDy.x)/determinant;
    if(dot(along,along)<1e-10) return 1.0;
    float angle=atan(along.y,along.x);
    return floor((angle+3.14159265)*(254.0/6.28318530)+0.5)/255.0;
}

vec2 decodeWaterFlow(float stored) {
    float code=floor(stored*255.0+0.5);
    if(code>254.5) return vec2(0.0);
    float angle=code*(6.28318530/254.0)-3.14159265;
    return vec2(cos(angle),sin(angle));
}
#endif
